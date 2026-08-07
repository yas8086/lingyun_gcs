cmake_minimum_required(VERSION 3.16)
project(lingyun_ground_station LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets PrintSupport SerialPort Test)

add_executable(lingyun_ground_station
    src/main.cpp
    src/model/telemetry_data.cpp
    src/comms/frame_parser.cpp
    src/comms/json_decoder.cpp
    src/comms/serial_manager.cpp
    src/core/data_bus.cpp
    src/core/alarm_engine.cpp
    src/core/recorder.cpp
    src/core/replay_engine.cpp
    src/core/config_manager.cpp
    src/ui/chart_widget.cpp
    src/ui/status_bar.cpp
    src/ui/device_panel.cpp
    third_party/qcustomplot/qcustomplot.cpp
)

target_link_libraries(lingyun_ground_station PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::PrintSupport Qt6::SerialPort
)

target_include_directories(lingyun_ground_station PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/qcustomplot
)

include(CTest)

if(BUILD_TESTING)
    include(tests/tests.cmake)
endif()
