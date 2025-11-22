cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
./build/run_keyword_benchmark
./build/run_person_detection_benchmark