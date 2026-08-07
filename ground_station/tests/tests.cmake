# 单元测试配置：本文件被主 CMakeLists 通过 include() 引入，
# 因此 CMAKE_CURRENT_SOURCE_DIR 指向 ground_station/（主目录）。
find_package(Qt6 REQUIRED COMPONENTS Test)

function(add_qt_test name)
    add_executable(${name} ${ARGN})
    target_link_libraries(${name} PRIVATE Qt6::Test Qt6::Core)
    target_include_directories(${name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_test(NAME ${name} COMMAND ${name})
endfunction()

add_qt_test(test_frame_parser tests/test_frame_parser.cpp src/comms/frame_parser.cpp)
add_qt_test(test_json_decoder tests/test_json_decoder.cpp src/comms/json_decoder.cpp src/model/telemetry_data.cpp)
