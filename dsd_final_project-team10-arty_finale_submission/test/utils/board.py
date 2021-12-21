import platform
import glob
import serial
from utils.scale_uart import *

# Enumerate ports 
def get_port_list():
    os_name = platform.system()
    if "Windows" in os_name:
        print("Current OS: Windows")
        ports = ['COM%s' %(i+1) for i in range(256)]
    elif "Linux"in os_name:
        print("Current OS: Linux")
        ports = glob.glob('/dev/tty[A-Za-z]*')
    elif "Darwin" in os_name:
        print("Current OS: Mac")
        ports = glob.glob('/dev/tty.*')
    result = []
    for p in ports:
        try:
            s = serial.Serial(p)
            s.close()
            result.append(p)
        except (OSError, serial.SerialException):
            pass
    print(result)
    return result
  
# First, Set the connection configuration and Port
# PORT-name may be vary depending on your systems.
# USE USB serial port.
def get_scale_uart(port_list):
    for pname in port_list:
        if 'Bluetooth' in str(pname):
            continue
            
        try:
            SU = Scale_UART(str(pname))
            print("%s port connected!" %(pname))
            return SU
        except serial.SerialException:
            print("%s port cannot be connected." %(pname))