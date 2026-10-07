cmake_minimum_required(VERSION 3.22.1)
project("termux_pty")

add_library(termux_pty SHARED termux_pty.cpp)
target_link_libraries(termux_pty log)

# The fast mode's chroot helper is a program, not a library. Named like one
# and written next to the libraries, it is packaged and extracted with them
# into nativeLibraryDir, where it can be executed (as libproot_exec.so is).
add_executable(moru_chroot moru_chroot.c)
set_target_properties(moru_chroot PROPERTIES
    OUTPUT_NAME "libmoru_chroot.so"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
