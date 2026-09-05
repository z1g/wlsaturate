cmake_minimum_required(VERSION 3.20)
project(wlsaturation VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(ECM 6.0.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons)
find_package(KWin REQUIRED)

kcoreaddons_add_plugin(wlsaturation
    SOURCES
        src/main.cpp
        src/saturationeffect.cpp
        src/saturation.qrc
    INSTALL_NAMESPACE "kwin/effects/plugins"
)

target_include_directories(wlsaturation PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(wlsaturation PRIVATE
    KWin::kwin
    KF6::ConfigCore
    Qt6::Core
    Qt6::Gui
)

install(PROGRAMS tools/wlsaturation DESTINATION ${KDE_INSTALL_BINDIR})
