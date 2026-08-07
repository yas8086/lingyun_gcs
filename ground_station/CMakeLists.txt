cmake_minimum_required(VERSION 3.16)
project(lingyun_ground_station LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets PrintSupport Test)

add_executable(lingyun_ground_station
    src/main.cpp
    src/model/telemetry_data.cpp
    third_party/qcustomplot/qcustomplot.cpp
)

target_link_libraries(lingyun_ground_station PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::PrintSupport
)

target_include_directories(lingyun_ground_station PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/qcustomplot
)

include(CTest)

if(BUILD_TESTING)
    include(tests/tests.cmake)
endif()
