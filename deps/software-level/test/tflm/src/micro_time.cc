#include "tensorflow/lite/micro/micro_time.h"
#include "hbird_sdk_soc.h"

namespace tflite
{

    uint32_t ticks_per_second() { return SystemCoreClock; }

    uint32_t GetCurrentTimeTicks() { return __get_rv_cycle(); }

} // namespace tflite
