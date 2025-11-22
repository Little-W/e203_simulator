// See LICENSE for license details.
#include <stdio.h>
#include "hbird_sdk_soc.h"
#include "hbirdv2_gpio.h"
#include "tflm_benchmark.h"

#define mtimer_irq_handler     core_mtip_handler
#define LED_GPIO GPIOA
#define LED_MASK 0x0F  // GPIOA 0-3

static uint8_t led_pos = 0;

void mtimer_irq_handler(void)
{
    // 清除所有LED
    gpio_write(LED_GPIO, LED_MASK, 0);
    // 点亮当前LED
    gpio_write(LED_GPIO, (1 << led_pos), (1 << led_pos));
    // 下一个LED
    led_pos = (led_pos + 1) % 4;

    // 重新设置定时器，0.5s后中断
    uint64_t now = SysTimer_GetLoadValue();
    SysTimer_SetCompareValue(now + (uint64_t)(0.5 * SOC_TIMER_FREQ));
}

void setup_led_gpio()
{
    // 配置GPIOA 0-3为输出
    gpio_enable_output(LED_GPIO, LED_MASK);
    // 熄灭所有LED
    gpio_write(LED_GPIO, LED_MASK, 0);
}

void setup_timer()
{
    uint64_t now = SysTimer_GetLoadValue();
    SysTimer_SetCompareValue(now + (uint64_t)(0.5 * SOC_TIMER_FREQ));
}

int main(void)
{
    // 初始化LED GPIO
    setup_led_gpio();

    // 注册定时器中断
    Core_Register_IRQ(SysTimer_IRQn, mtimer_irq_handler);

    // 使能全局中断
    __enable_irq();

    // 初始化定时器
    setup_timer();

    while(1)
    {
        printf("Hello E203!\r\n");
        tflm_benchmark();
        printf("Goodbye E203!\r\n");
    }

    return 0;
}

