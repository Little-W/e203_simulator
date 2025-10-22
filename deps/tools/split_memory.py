#!/usr/bin/env python3
"""
内存分割脚本 - 将.verilog或.hex文件分割为ilm、extram和ram三部分
用法: python3 split_memory.py <verilog_file|hex_file>
"""

import sys
import os
import re
from pathlib import Path
from typing import Dict, Tuple, Optional

# 定义内存区域配置
MEMORY_REGIONS = {
    'ilm': {
        'start': 0x80000000,
        'size': 64 * 1024,  # 256KB
    },
    'extram': {
        'start': 0x00080000,
        'size': 512 * 1024,  # 512KB
    },
    'ram': {
        'start': 0x90000000,
        'size': 64 * 1024,  # 256KB
    }
}


class HexParser:
    """Intel HEX格式解析器"""
    
    @staticmethod
    def parse_hex_line(line: str) -> Optional[Tuple[int, bytes]]:
        """
        解析Intel HEX格式的一行
        返回: (address, data_bytes) 或 None
        """
        line = line.strip()
        if not line.startswith(':'):
            return None
        
        try:
            # Intel HEX格式: :LLAAAATT[DD...]CC
            # LL = 字节数, AAAA = 地址, TT = 记录类型, DD = 数据, CC = 校验和
            byte_count = int(line[1:3], 16)
            address = int(line[3:7], 16)
            record_type = int(line[7:9], 16)
            
            # 只处理数据记录 (type 00)
            if record_type != 0x00:
                return None
            
            # 提取数据字节
            data_bytes = bytes.fromhex(line[9:9+byte_count*2])
            
            return (address, data_bytes)
        except (ValueError, IndexError):
            return None
    
    @staticmethod
    def read_hex_file(filepath: Path) -> Dict[int, int]:
        """
        读取整个hex文件，返回地址到字节的映射
        返回: {absolute_address: byte_value}
        """
        memory = {}
        extended_address = 0
        
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line.startswith(':'):
                    continue
                
                try:
                    byte_count = int(line[1:3], 16)
                    address = int(line[3:7], 16)
                    record_type = int(line[7:9], 16)
                    
                    # 扩展线性地址记录 (type 04)
                    if record_type == 0x04:
                        extended_address = int(line[9:13], 16) << 16
                        continue
                    
                    # 数据记录 (type 00)
                    if record_type == 0x00:
                        full_address = extended_address + address
                        data_hex = line[9:9+byte_count*2]
                        
                        for i in range(byte_count):
                            byte_val = int(data_hex[i*2:i*2+2], 16)
                            memory[full_address + i] = byte_val
                    
                    # 文件结束记录 (type 01)
                    elif record_type == 0x01:
                        break
                        
                except (ValueError, IndexError):
                    continue
        
        # 打印地址范围
        if memory:
            min_addr = min(memory.keys())
            max_addr = max(memory.keys())
            print(f"  Data range: 0x{min_addr:08x} - 0x{max_addr:08x} ({len(memory)} bytes)")
        
        return memory


class MemorySplitter:
    def __init__(self, input_file: str):
        self.input_file = Path(input_file)
        self.dir = self.input_file.parent
        self.basename = self.input_file.stem
        suffix = self.input_file.suffix.lower()
        self.is_hex = suffix == '.hex'
        
        # 初始化内存区域配置，自动计算end
        self.memory_regions = {}
        for name, config in MEMORY_REGIONS.items():
            self.memory_regions[name] = config.copy()
            self.memory_regions[name]['end'] = config['start'] + config['size'] - 1
        
        # 初始化每个区域的数据结构
        self.regions = {}
        for region_name in self.memory_regions.keys():
            self.regions[region_name] = {
                'bytes': {},  # 字典存储字节数据 {relative_addr: byte_hex}
                'count': 0,
                'min_addr': None,
                'max_addr': None,
                'last_addr': None,
                'verilog_file': self.dir / f"{self.basename}_{region_name}.verilog",
                'mem_file': self.dir / f"{self.basename}_{region_name}.mem",
            }
    
    def check_output_exists(self) -> bool:
        """检查输出文件是否已存在"""
        for region in self.regions.values():
            if region['verilog_file'].exists() or region['mem_file'].exists():
                return True
        return False
    
    def get_region_for_address(self, addr: int) -> Optional[str]:
        """根据地址返回所属的内存区域名称"""
        for region_name, config in self.memory_regions.items():
            if config['start'] <= addr <= config['end']:
                return region_name
        return None
    
    def process_byte(self, addr: int, byte_hex: str, verilog_handlers: Dict):
        """处理单个字节数据"""
        region_name = self.get_region_for_address(addr)
        if region_name is None:
            return
        
        region = self.regions[region_name]
        relative_addr = addr - MEMORY_REGIONS[region_name]['start']
        
        # 检查是否需要输出地址标记
        if region['last_addr'] is None or relative_addr != region['last_addr'] + 1:
            verilog_handlers[region_name].write(f"@{relative_addr:08x}\n")
        
        # 写入数据
        verilog_handlers[region_name].write(f"{byte_hex}\n")
        
        # 更新数据结构
        region['bytes'][relative_addr] = byte_hex
        region['count'] += 1
        region['last_addr'] = relative_addr
        
        # 更新最小最大地址
        if region['min_addr'] is None or relative_addr < region['min_addr']:
            region['min_addr'] = relative_addr
        if region['max_addr'] is None or relative_addr > region['max_addr']:
            region['max_addr'] = relative_addr
    
    def parse_and_split(self):
        """解析输入文件并分割到不同区域"""
        print(f"Processing {self.input_file}...")
        for region_name, config in self.memory_regions.items():
            print(f"{region_name.upper()} range: 0x{config['start']:08x} - 0x{config['end']:08x}")
        
        # 打开所有输出文件
        verilog_handlers = {}
        for region_name, region in self.regions.items():
            verilog_handlers[region_name] = open(region['verilog_file'], 'w')
        
        try:
            current_addr = 0
            
            with open(self.input_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    
                    # 跳过空行和注释
                    if not line or line.startswith('//'):
                        continue
                    
                    # 处理地址行 @address
                    addr_match = re.match(r'^@([0-9a-fA-F]+)\s*$', line)
                    if addr_match:
                        current_addr = int(addr_match.group(1), 16)
                        continue
                    
                    # 处理带地址的数据行 @address data...
                    addr_data_match = re.match(r'^@([0-9a-fA-F]+)\s+((?:[0-9a-fA-F]{2}\s*)+)', line)
                    if addr_data_match:
                        current_addr = int(addr_data_match.group(1), 16)
                        data_str = addr_data_match.group(2)
                    else:
                        # 处理纯数据行
                        data_match = re.match(r'^((?:[0-9a-fA-F]{2}\s*)+)', line)
                        if data_match:
                            data_str = data_match.group(1)
                        else:
                            continue
                    
                    # 提取所有字节
                    bytes_list = re.findall(r'[0-9a-fA-F]{2}', data_str)
                    for byte_hex in bytes_list:
                        self.process_byte(current_addr, byte_hex, verilog_handlers)
                        current_addr += 1
        
        finally:
            # 关闭所有文件
            for handler in verilog_handlers.values():
                handler.close()
        
        # 输出统计信息
        print("\nMemory split completed:")
        for region_name, region in self.regions.items():
            print(f"  {region_name.upper()}: {region['verilog_file']} ({region['count']} entries)")
    
    def process_hex_file(self):
        """处理hex文件"""
        print(f"Processing HEX file {self.input_file}...")
        for region_name, config in self.memory_regions.items():
            print(f"{region_name.upper()} range: 0x{config['start']:08x} - 0x{config['end']:08x}")
        
        # 读取hex文件
        memory = HexParser.read_hex_file(self.input_file)
        
        if not memory:
            print("Warning: No data found in hex file")
            return
        
        print(f"Loaded {len(memory)} bytes from hex file")
        
        # 打开所有输出文件
        verilog_handlers = {}
        for region_name, region in self.regions.items():
            verilog_handlers[region_name] = open(region['verilog_file'], 'w')
        
        try:
            # 按地址排序处理
            sorted_addresses = sorted(memory.keys())
            
            for addr in sorted_addresses:
                byte_val = memory[addr]
                byte_hex = f"{byte_val:02x}"
                self.process_byte(addr, byte_hex, verilog_handlers)
        
        finally:
            # 关闭所有文件
            for handler in verilog_handlers.values():
                handler.close()
        
        # 输出统计信息
        print("\nMemory split completed:")
        for region_name, region in self.regions.items():
            print(f"  {region_name.upper()}: {region['verilog_file']} ({region['count']} entries)")
    
    def generate_mem_files(self):
        """生成.mem格式文件
           - ILM: 64位一行（8字节，小端序）
           - 其他: 32位一行（4字节，小端序）
        """
        for region_name, region in self.regions.items():
            with open(region['mem_file'], 'w') as f:
                if region['min_addr'] is None:
                    f.write("// No data found\n")
                    continue

                addr = region['min_addr']
                step = 8 if region_name == 'ilm' else 4  # ILM 64位一行，其余32位一行
                while addr <= region['max_addr']:
                    # 按小端序组合：收集 step 个字节后整体反转
                    bytes_vals = [region['bytes'].get(addr + i, '00') for i in range(step)]
                    word = "".join(reversed(bytes_vals)) + "\n"
                    f.write(word)
                    addr += step
    
    def add_placeholders(self):
        """为空的区域添加占位符"""
        for region_name, region in self.regions.items():
            if region['count'] == 0:
                with open(region['verilog_file'], 'w') as f:
                    f.write(f"// No {region_name.upper()} data found\n")
    
    def run(self):
        """执行完整的分割流程"""
        if self.check_output_exists():
            print("Output files already exist, aborting to avoid overwrite.")
            return 0
        
        try:
            if self.is_hex:
                self.process_hex_file()
            else:
                self.parse_and_split()
            
            self.generate_mem_files()
            self.add_placeholders()
            return 0
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
            return 1


def main():
    import argparse
    parser = argparse.ArgumentParser(description="内存分割脚本 - 将.verilog或.hex文件分割为ilm、extram和ram三部分")
    parser.add_argument("input_file", help="输入的.verilog或.hex文件路径")
    parser.add_argument("--force", action="store_true", help="覆盖已存在的输出文件")
    args = parser.parse_args()

    input_file = args.input_file
    if not os.path.isfile(input_file):
        print(f"Error: File {input_file} not found")
        return 1

    # 检查文件格式
    suffix = Path(input_file).suffix.lower()
    if suffix not in ['.hex', '.verilog']:
        print(f"Warning: File extension {suffix} not recognized, expected .hex or .verilog")

    splitter = MemorySplitter(input_file)
    if splitter.check_output_exists() and not args.force:
        print("Output files already exist, aborting to avoid overwrite.\n如需覆盖请加 --force 参数。")
        return 0

    # 如果需要覆盖，先删除已存在的输出文件
    if args.force:
        for region in splitter.regions.values():
            for fpath in [region['verilog_file'], region['mem_file']]:
                try:
                    if fpath.exists():
                        fpath.unlink()
                except Exception:
                    pass

    return splitter.run()


if __name__ == '__main__':
    sys.exit(main())
