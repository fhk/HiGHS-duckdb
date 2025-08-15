#include <iostream>
#include "submodules/highs/highs/Highs.h"

int main() {
    std::cout << "Testing HiGHS integration..." << std::endl;
    
    // Test basic HiGHS functionality
    std::cout << "HiGHS version: " << highsVersion() << std::endl;
    
    // Create a simple LP problem to test compilation
    Highs highs;
    std::cout << "HiGHS object created successfully!" << std::endl;
    
    return 0;
}