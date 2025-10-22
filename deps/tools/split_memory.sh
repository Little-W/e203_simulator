#!/bin/bash

# 内存分割脚本 - 将.verilog文件分割为ilm、extram和ram三部分
# 参数: $1 = 输入的.verilog文件路径

if [ $# -ne 1 ]; then
    echo "Usage: $0 <verilog_file>"
    exit 1
fi

input_file="$1"
if [ ! -f "$input_file" ]; then
    echo "Error: File $input_file not found"
    exit 1
fi

# 获取文件名和目录
dir=$(dirname "$input_file")
basename=$(basename "$input_file" .verilog)

# 输出文件
ilm_file="${dir}/${basename}_ilm.verilog"
extram_file="${dir}/${basename}_extram.verilog"
ram_file="${dir}/${basename}_ram.verilog"
ilm_mem_file="${dir}/${basename}_ilm.mem"
extram_mem_file="${dir}/${basename}_extram.mem"
ram_mem_file="${dir}/${basename}_ram.mem"

# 如果输出文件已存在，则直接退出，避免重复操作
if [ -f "$ilm_file" ] || [ -f "$extram_file" ] || [ -f "$ram_file" ] || [ -f "$ilm_mem_file" ] || [ -f "$extram_mem_file" ] || [ -f "$ram_mem_file" ]; then
    echo "Output files already exist, aborting to avoid overwrite."
    exit 0
fi

# 定义地址范围 (按字节地址计算)
# ILM: 0x80000000 - 0x8000FFFF (64KB)
# EXTRAM: 0x00080000 - 0x000FFFFF (512KB)  
# RAM: 0x90000000 - 0x9000FFFF (64KB)
ILM_START=$((0x80000000))
ILM_END=$((0x8000FFFF))
EXTRAM_START=$((0x00080000))
EXTRAM_END=$((0x000FFFFF))
RAM_START=$((0x90000000))
RAM_END=$((0x9000FFFF))

# 清空输出文件
> "$ilm_file"
> "$extram_file"
> "$ram_file"
> "$ilm_mem_file"
> "$extram_mem_file"
> "$ram_mem_file"

echo "Processing $input_file..."
echo "ILM range: 0x$(printf '%08x' $ILM_START) - 0x$(printf '%08x' $ILM_END)"
echo "EXTRAM range: 0x$(printf '%08x' $EXTRAM_START) - 0x$(printf '%08x' $EXTRAM_END)"
echo "RAM range: 0x$(printf '%08x' $RAM_START) - 0x$(printf '%08x' $RAM_END)"

current_addr=0
ilm_count=0
extram_count=0
ram_count=0
# 跟踪上一次写入的地址
last_ilm_addr=-1
last_extram_addr=-1
last_ram_addr=-1

# 用于收集所有字节数据（普通数组，地址即下标）
declare -a ilm_bytes_arr
declare -a extram_bytes_arr
declare -a ram_bytes_arr
ilm_min_addr=-1
ilm_max_addr=-1
extram_min_addr=-1
extram_max_addr=-1
ram_min_addr=-1
ram_max_addr=-1

# 读取输入文件并分割
while IFS= read -r line; do
    # 跳过空行和注释行
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*// ]]; then
        continue
    fi
    
    # 处理地址行 (格式: @address)
    if [[ "$line" =~ ^@([0-9a-fA-F]+)[[:space:]]*$ ]]; then
        addr_hex="${BASH_REMATCH[1]}"
        # 转换地址为十进制
        current_addr=$((16#$addr_hex))
        continue
    fi
    
    # 处理数据行 (格式: 多个十六进制字节，如 EF EF 00 00)
    if [[ "$line" =~ ^@([0-9a-fA-F]+)[[:space:]]+(([0-9a-fA-F]{2}[[:space:]]*)+) ]]; then
        # 带地址的数据行
        addr_hex="${BASH_REMATCH[1]}"
        data_str="${BASH_REMATCH[2]}"
        current_addr=$((16#$addr_hex))
    elif [[ "$line" =~ ^(([0-9a-fA-F]{2}[[:space:]]*)+) ]]; then
        # 纯数据行
        data_str="${BASH_REMATCH[1]}"
    else
        continue
    fi
    
    # 处理数据字符串中的每个字节
    # 清理所有空白和换行，只保留字节
    clean_data_str=$(echo "$data_str" | tr -s ' \t\r\n' ' ')
    read -ra bytes_arr <<< "$clean_data_str"
    for byte in "${bytes_arr[@]}"; do
        if [ $current_addr -ge $ILM_START ] && [ $current_addr -le $ILM_END ]; then
            relative_addr=$((current_addr - ILM_START))
            if [ $last_ilm_addr -eq -1 ] || [ $relative_addr -ne $((last_ilm_addr + 1)) ]; then
                # 如果是首次写入或地址不连续，输出地址标记
                echo "@$(printf '%08x' $relative_addr)" >> "$ilm_file"
            fi
            # 输出数据
            echo "$byte" >> "$ilm_file"
            ilm_bytes_arr[$relative_addr]="$byte"
            if [ $ilm_min_addr -eq -1 ] || [ $relative_addr -lt $ilm_min_addr ]; then
                ilm_min_addr=$relative_addr
            fi
            if [ $ilm_max_addr -eq -1 ] || [ $relative_addr -gt $ilm_max_addr ]; then
                ilm_max_addr=$relative_addr
            fi
            last_ilm_addr=$relative_addr
            ilm_count=$((ilm_count + 1))
        elif [ $current_addr -ge $EXTRAM_START ] && [ $current_addr -le $EXTRAM_END ]; then
            # EXTRAM区域 - 转换为相对地址
            relative_addr=$((current_addr - EXTRAM_START))
            if [ $last_extram_addr -eq -1 ] || [ $relative_addr -ne $((last_extram_addr + 1)) ]; then
                # 如果是首次写入或地址不连续，输出地址标记
                echo "@$(printf '%08x' $relative_addr)" >> "$extram_file"
            fi
            # 输出数据
            echo "$byte" >> "$extram_file"
            extram_bytes_arr[$relative_addr]="$byte"
            if [ $extram_min_addr -eq -1 ] || [ $relative_addr -lt $extram_min_addr ]; then
                extram_min_addr=$relative_addr
            fi
            if [ $extram_max_addr -eq -1 ] || [ $relative_addr -gt $extram_max_addr ]; then
                extram_max_addr=$relative_addr
            fi
            last_extram_addr=$relative_addr
            extram_count=$((extram_count + 1))
        elif [ $current_addr -ge $RAM_START ] && [ $current_addr -le $RAM_END ]; then
            # RAM区域 - 转换为相对地址
            relative_addr=$((current_addr - RAM_START))
            if [ $last_ram_addr -eq -1 ] || [ $relative_addr -ne $((last_ram_addr + 1)) ]; then
                # 如果是首次写入或地址不连续，输出地址标记
                echo "@$(printf '%08x' $relative_addr)" >> "$ram_file"
            fi
            # 输出数据
            echo "$byte" >> "$ram_file"
            ram_bytes_arr[$relative_addr]="$byte"
            if [ $ram_min_addr -eq -1 ] || [ $relative_addr -lt $ram_min_addr ]; then
                ram_min_addr=$relative_addr
            fi
            if [ $ram_max_addr -eq -1 ] || [ $relative_addr -gt $ram_max_addr ]; then
                ram_max_addr=$relative_addr
            fi
            last_ram_addr=$relative_addr
            ram_count=$((ram_count + 1))
        fi
        current_addr=$((current_addr + 1))
    done
    
done < "$input_file"

echo "Memory split completed:"
echo "  ILM: $ilm_file ($ilm_count entries)"
echo "  EXTRAM: $extram_file ($extram_count entries)"
echo "  RAM: $ram_file ($ram_count entries)"

# 更高效的mem输出函数
output_mem_file_arr() {
    local -n bytes_arr=$1
    local min_addr=$2
    local max_addr=$3
    local mem_file="$4"
    if [ $min_addr -eq -1 ]; then
        echo "// No data found" > "$mem_file"
        return
    fi
    > "$mem_file"
    local addr=$min_addr
    while [ $addr -le $max_addr ]; do
        # 取4字节
        byte0=${bytes_arr[$addr]:-00}
        byte1=${bytes_arr[$((addr+1))]:-00}
        byte2=${bytes_arr[$((addr+2))]:-00}
        byte3=${bytes_arr[$((addr+3))]:-00}
        printf "%s%s%s%s\n" "$byte3" "$byte2" "$byte1" "$byte0" >> "$mem_file"
        addr=$((addr + 4))
    done
}

# 输出ILM、EXTRAM和RAM的mem文件（使用数组版本）
output_mem_file_arr ilm_bytes_arr $ilm_min_addr $ilm_max_addr "$ilm_mem_file"
output_mem_file_arr extram_bytes_arr $extram_min_addr $extram_max_addr "$extram_mem_file"
output_mem_file_arr ram_bytes_arr $ram_min_addr $ram_max_addr "$ram_mem_file"

# 如果各区域文件为空，创建一个空的占位符
if [ $extram_count -eq 0 ]; then
    echo "// No EXTRAM data found" > "$extram_file"
fi

if [ $ilm_count -eq 0 ]; then
    echo "// No ILM data found" > "$ilm_file"
fi

if [ $ram_count -eq 0 ]; then
    echo "// No RAM data found" > "$ram_file"
fi