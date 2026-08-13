cmake_minimum_required(VERSION 3.16)
project(lingyun_ground_station LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets SerialPort Test
             Quick Qml QuickControls2 Charts Network)

include(CTest)

if(BUILD_TESTING)
    include(tests/tests.cmake)
endif()

# ===== QML 版地面站（复刻原型视觉，Qt Quick + QtCharts）=====
add_executable(lingyun_gcs_qml
    src/qml/main.cpp
    src/model/telemetry_data.cpp
    src/comms/frame_parser.cpp
    src/comms/json_decoder.cpp
    src/comms/serial_manager.cpp
    src/core/data_bus.cpp
    src/core/alarm_engine.cpp
    src/core/config_manager.cpp
    src/map/tile_provider.cpp
    src/qmlbridge/telemetry_bridge.cpp
)

qt_add_resources(lingyun_gcs_qml "qml_res"
    PREFIX "/qml"
    BASE src/qml
    FILES src/qml/main.qml
          src/qml/views/MonitorView.qml
          src/qml/views/SelfCheckView.qml
          src/qml/views/MapView.qml
          src/qml/views/FlightView.qml
          src/qml/views/TopoView.qml
          src/qml/views/SettingsView.qml
          src/qml/img/airship.svg
          src/qml/img/airship-blue.svg
          src/qml/img/flight-data.svg
)

target_link_libraries(lingyun_gcs_qml PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Charts Qt6::SerialPort Qt6::Network
)

target_include_directories(lingyun_gcs_qml PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
