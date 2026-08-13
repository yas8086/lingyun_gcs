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
add_qt_test(test_alarm_engine tests/test_alarm_engine.cpp src/core/alarm_engine.cpp src/model/telemetry_data.cpp)
# alarm_engine 依赖 QApplication::beep（Qt6::Widgets）
target_link_libraries(test_alarm_engine PRIVATE Qt6::Widgets)
add_qt_test(test_config_manager tests/test_config_manager.cpp src/core/config_manager.cpp src/core/alarm_engine.cpp src/model/telemetry_data.cpp)
target_link_libraries(test_config_manager PRIVATE Qt6::Widgets)
# 集成测试：模拟器帧 → 解码 → 桥接层暴露（需 QApplication）
add_qt_test(test_bridge_integration tests/test_bridge_integration.cpp src/comms/frame_parser.cpp src/comms/json_decoder.cpp src/comms/serial_manager.cpp src/model/telemetry_data.cpp src/core/config_manager.cpp src/core/alarm_engine.cpp src/qmlbridge/telemetry_bridge.cpp)
target_link_libraries(test_bridge_integration PRIVATE Qt6::Widgets Qt6::SerialPort)
