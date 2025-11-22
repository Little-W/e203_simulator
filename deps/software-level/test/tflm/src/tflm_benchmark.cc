#include "tflm_benchmark.h"
#include <stdio.h>

// TensorFlow Lite Micro 原始示例
extern int keyword_benchmark_main(int argc, char** argv);
extern int person_detection_benchmark_main(int argc, char** argv);
extern int person_detection_test_main(int argc, char** argv);

// 自定义模型示例
extern int my_model_main(int argc, char** argv);

void tflm_benchmark()
{
    puts("==============================================================");
    puts("                TensorFlow Lite for Microcontrollers");
    puts("                library and benchmarks porting");
    puts("                for Hbird E203 RISC-V core");
    puts("--------------------------------------------------------------");

#ifdef KEYWORD_BENCHMARK
    printf(" keyword benchmark ...\n");
    puts("--------------------------------------------------------------");
    keyword_benchmark_main(0, nullptr);
#endif

#ifdef PERSON_DETECTION_BENCHMARK
    puts(" person detection benchmark ...");
    puts("--------------------------------------------------------------");
    person_detection_benchmark_main(0, nullptr);
#endif

#ifdef PERSON_DETECTION_TEST
    puts(" person detection test ...");
    puts("--------------------------------------------------------------");
    person_detection_test_main(0, nullptr);
#endif

#ifdef MY_MODEL_TEST
    puts(" my custom model test ...");
    puts("--------------------------------------------------------------");
    my_model_main(0, nullptr);
#endif
    puts("==============================================================");
}
