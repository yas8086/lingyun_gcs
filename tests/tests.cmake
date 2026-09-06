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
# 测试用 QStandardPaths::setTestModeEnabled 把配置写到 ~/.qttest/。
# 在沙箱/受限 HOME 下删除/写入可能被拦截，导致 defaults() 读到残留配置而失败。
# 将 HOME 重定向到可写的 build 子目录，保证测试配置目录可读写、用例间互相隔离。
set(_test_home "${CMAKE_BINARY_DIR}/.testhome")
file(MAKE_DIRECTORY "${_test_home}")
set_tests_properties(test_config_manager PROPERTIES ENVIRONMENT "HOME=${_test_home}")
unset(_test_home)
# 集成测试：模拟器帧 → 解码 → 桥接层暴露（需 QApplication）
add_qt_test(test_bridge_integration tests/test_bridge_integration.cpp src/comms/frame_parser.cpp src/comms/json_decoder.cpp src/comms/serial_manager.cpp src/comms/udp_link_source.cpp src/model/telemetry_data.cpp src/core/config_manager.cpp src/core/alarm_engine.cpp src/qmlbridge/telemetry_bridge.cpp src/qmlbridge/telemetry_bridge_config.cpp src/qmlbridge/telemetry_bridge_rules.cpp src/qmlbridge/telemetry_bridge_record.cpp src/video/rtsp_stream.cpp src/video/rtsp_recorder.cpp src/video/siyi_sdk_client.cpp src/video/skydroid_sdk_client.cpp)
target_link_libraries(test_bridge_integration PRIVATE Qt6::Widgets Qt6::SerialPort Qt6::Network PkgConfig::GST)
# Windows：telemetry_bridge 的网口链路检测用 IP Helper API
if(WIN32)
    target_link_libraries(test_bridge_integration PRIVATE iphlpapi)
endif()

# 视频/云台协议回环测试（UDP 本地回环，无需真机；验证命令构造、回包解析、CRC 校验）
add_qt_test(test_video_protocol tests/test_video_protocol.cpp src/video/siyi_sdk_client.cpp src/video/skydroid_sdk_client.cpp)
target_link_libraries(test_video_protocol PRIVATE Qt6::Network)

# 数据总线 / 瓦片缓存 / 串口辅助 / UDP 网口源测试（无头可运行）
add_qt_test(test_core_aux tests/test_core_aux.cpp src/core/data_bus.cpp src/map/tile_provider.cpp src/comms/serial_manager.cpp src/comms/udp_link_source.cpp src/comms/frame_parser.cpp src/comms/json_decoder.cpp src/model/telemetry_data.cpp)
target_link_libraries(test_core_aux PRIVATE Qt6::SerialPort Qt6::Network)

# C3：QApplication 类测试在无头/CI 环境需 offscreen 平台插件（无 DISPLAY 时 QTEST_MAIN 启动失败）
set_tests_properties(test_alarm_engine test_bridge_integration
    PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
