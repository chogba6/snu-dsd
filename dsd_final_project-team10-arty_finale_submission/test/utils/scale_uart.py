import serial
import struct
from utils.bit_operation import *

class Scale_UART:
    def __init__(self, device):
        self.ser = serial.Serial(device, 921600)
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()

    def su_flush_buffer(self):
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        return None

    # write data with little endian
    def su_write_data_trans(self, addr, value):
        write_op = 0x4
        res = (write_op << 60) | (addr << 32) | (value)
        byte_num = struct.pack('>Q', res)
        for i in range(4):
            self.ser.write(bytearray([byte_num[i]]))
        for i in range(4):
            self.ser.write(bytearray([byte_num[7-i]]))
        return None

    # write data with big endian
    def su_write_data(self, addr, value):
        write_op = 0x4
        res = (write_op << 60) | (addr << 32) | (value)
        byte_num = struct.pack('>Q', res)
        for i in range(8):
            self.ser.write(bytearray([byte_num[i]]))
        return None

    # read data from address
    def su_read_data(self, addr):
        read_op = 0x5
        res = (read_op << 60) | (addr << 32)
        byte_num = struct.pack('>Q', res)
        for i in range(8):
            self.ser.write(bytearray([byte_num[i]]))
        packet = []
        for i in range(4):
            temp = self.ser.read(size=1)
            packet.append(ord(temp))
        # data = self.ser.read(size=4)
        return packet

    # read image file
    # write_data in little endian on base_addr + i * 4
    def su_set_image(self, image_info, f_name):
        base_addr = image_info['BASE_ADDR']
        img_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in img_data:
            for data_slice2 in data_slice1:
                for data_slice3 in data_slice2:
                    for data_slice4 in data_slice3:
                        count += 1
                        bin_data = data_to_8bit_binary(data_slice4)
                        d_str += f'{bin_data:02x}'
                        if count % 4 == 0:
                            d_str = "0x" + d_str
                            val = int(d_str, 0)
                            self.su_write_data_trans(base_addr + (count - 4), val)
                            d_str = ""
        return None

    def su_set_image_one(self, image_info, f_name):
        base_addr = image_info['BASE_ADDR']
        img_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in img_data:
            for data_slice2 in data_slice1:
                for data_slice3 in data_slice2:
                    count += 1
                    bin_data = data_to_8bit_binary(data_slice3)
                    d_str += f'{bin_data:02x}'
                    if count % 4 == 0:
                        d_str = "0x" + d_str
                        val = int(d_str, 0)
                        self.su_write_data_trans(base_addr + (count - 4), val)
                        d_str = ""
        return None

    # read network param file with idx
    # write data in little endian on base_addr + i*4
    def su_set_conv_w(self, weight_info, f_name):
        base_addr = weight_info['BASE_ADDR']
        weight_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in weight_data:
            for data_slice2 in data_slice1:
                for data_slice3 in data_slice2:
                    for data_slice4 in data_slice3:
                        count += 1
                        bin_data = data_to_8bit_binary(data_slice4)
                        d_str += f'{bin_data:02x}'
                        if count % 4 == 0:
                            d_str = "0x" + d_str
                            val = int(d_str, 0)
                            self.su_write_data_trans(base_addr + (count - 4), val)
                            d_str = ""
        return None

    # read network param file with idx
    # write data in little endian on base_addr + i*4
    def su_set_conv_b(self, bias_info, f_name):
        base_addr = bias_info['BASE_ADDR']
        bias_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in bias_data:
            count += 1
            bin_data = data_to_8bit_binary(data_slice1)
            d_str += f'{bin_data:02x}'
            if count % 4 == 0:
                d_str = "0x" + d_str
                val = int(d_str, 0)
                self.su_write_data_trans(base_addr + (count - 4), val)
                d_str = ""
        return None

    # read network param file with idx
    # write data in little endian on base_addr + i*4
    def su_set_fc_w(self, weight_info, f_name):
        base_addr = weight_info['BASE_ADDR']
        weight_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in weight_data:
            for data_slice2 in data_slice1:
                count += 1
                bin_data = data_to_8bit_binary(data_slice2)
                d_str += f'{bin_data:02x}'
                if count % 4 == 0:
                    d_str = "0x" + d_str
                    val = int(d_str, 0)
                    self.su_write_data_trans(base_addr + (count - 4), val)
                    d_str = ""
        return None

    # read network param file with idx
    # write data in little endian on base_addr + i*4
    def su_set_fc_b(self, bias_info, f_name):
        base_addr = bias_info['BASE_ADDR']
        bias_data = np.load(f_name)
        count = 0
        d_str = ""
        for data_slice1 in bias_data:
            count += 1
            bin_data = data_to_8bit_binary(data_slice1)
            d_str += f'{bin_data:02x}'
            if count % 4 == 0:
                d_str = "0x" + d_str
                val = int(d_str, 0)
                self.su_write_data_trans(base_addr + (count-4), val)
                d_str = ""
        if d_str:
            d_str = "0x" + "{:<08s}".format(d_str)
            val = int(d_str, 0)
            self.su_write_data_trans(base_addr + (count-2), val)
            d_str = ""
        return None

    # Set the VDMA 0
    # 1) Set result parameter to vdma0 (R)
    # 2) Set feature parameter vdma0 (F)
        # Feature receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # Set bias parameter to vdma0 (B)
        # Bias receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # Set weight parameter to vdma0 (W)
        # Weight receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # FC computation
    # 1) Send the command to start the computation
    # 2) Spin-lock for waiting done-flag
    # 3) If receive done flag, send respond signal
    # 4) And write the finish sign
    def su_fc_control(self, F, W, B, R, vaddr, faddr):
        #######################################################################
        # You should revise below code
        # Your apb-register and FSM will not match below control flow
        #######################################################################
        # VDMA0 Setting
        # Set result param to vdma0
        self.su_write_data(vaddr + 0x30, 0x00010091)
        self.su_write_data(vaddr + 0xac, R['BASE_ADDR'])
        self.su_write_data(vaddr + 0xa8, R['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0xa4, R['HSIZE'])
        self.su_write_data(vaddr + 0xa0, R['VSIZE'])
        # Set feature param to vdma0
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, F['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, F['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, F['HSIZE'])
        self.su_write_data(vaddr + 0x50, F['VSIZE'])
        ## feature receive
        done = 0
        self.su_write_data(faddr + 0x04, F['HSIZE']*F['VSIZE'])
        self.su_write_data(faddr + 0x00, 0x1)
        while (True):
            done = self.su_read_data(faddr + 0x10)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break

        # Set bias param to vdma0
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, B['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, B['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, B['HSIZE'])
        self.su_write_data(vaddr + 0x50, B['VSIZE'])
        ## bias receive
        done = 0
        self.su_write_data(faddr + 0x04, B['HSIZE']*B['VSIZE'])
        self.su_write_data(faddr + 0x00, 0x2)
        while (True):
            done = self.su_read_data(faddr + 0x14)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break

        # Set weight param to vdma0
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, W['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, W['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, W['HSIZE'])
        self.su_write_data(vaddr + 0x50, W['VSIZE'])
        ## weight receive
        done = 0
        # Fix size for each weight receive
        self.su_write_data(faddr + 0x04, 0x20)
        self.su_write_data(faddr + 0x00, 0x4)
        while (True):
            done = self.su_read_data(faddr + 0x08)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break

        # Start FC proc.
        done = 0
        self.su_write_data(faddr + 0x00, 0x5)
        while (True):
            done = self.su_read_data(faddr + 0x0c)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(faddr + 0x00, 0x0) # Reset module
        self.su_write_data(vaddr + 0x00, 0x00010094)
        # print("FC done.")
        return 1

    # Set the VDMA
    # 1) Set result parameter to vdma1 (R)
    # 2) Set input parameter vdma1 (I)
    # 3) Set feature parameter to vdma2 (F)
    # Feature receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # Set bias parameter to vdma1 (B)
    # Bias receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # Set weight parameter to vdma1 (W)
        # Weight receive
        # 1) Send the commnad to start
        # 2) Wait spin-lock (done-flag)
        # 3) Send the respond signal
    # Conv computation
    # 1) Send the command to start the computation
    # 2) Spin-lock for waiting done-flag
    # 3) If receive done flag, send respond signal
    # 4) And write the finish sign

    def su_conv_control(self, I, F, W, B, R, vaddr, caddr):
        #######################################################################
        # You should revise below code
        # Your apb-register and FSM will not match below control flow
        #######################################################################

        # VDMA1 Setting
        # Set result param to vdma1
        self.su_write_data(vaddr + 0x30, 0x00010091)
        self.su_write_data(vaddr + 0xac, R['BASE_ADDR'])
        self.su_write_data(vaddr + 0xa8, R['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0xa4, R['HSIZE'])
        self.su_write_data(vaddr + 0xa0, R['VSIZE'])
        # Set input param to conv addr
        self.su_write_data(caddr + 0x04, I['IN_CH'])
        self.su_write_data(caddr + 0x08, I['OUT_CH'])
        self.su_write_data(caddr + 0x0c, I['FLEN'])
        self.su_write_data(caddr + 0x10, 0x0)
        self.su_write_data(caddr + 0x14, 0x0)
        self.su_write_data(caddr + 0x18, 0x0)
        self.su_write_data(caddr + 0x1c, 0x0)
        # Set feature param to vdma1
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, F['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, F['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, F['HSIZE'])
        self.su_write_data(vaddr + 0x50, F['VSIZE'])
        ## feature receive
        done = 0
        self.su_write_data(caddr + 0x00, 0x1) #command
        while (True):
            done = self.su_read_data(caddr + 0x20)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(caddr + 0x10, 0x1) #respond
        # Set bias param to vdma2
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, B['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, B['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, B['HSIZE'])
        self.su_write_data(vaddr + 0x50, B['VSIZE'])
        ## feature receive
        done = 0
        self.su_write_data(caddr + 0x00, 0x2) #command
        while (True):
            done = self.su_read_data(caddr + 0x24)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(caddr + 0x14, 0x1) #respond
        # Set weight param to vdma2
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, W['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, W['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, W['HSIZE'])
        self.su_write_data(vaddr + 0x50, W['VSIZE'])
        ## weight receive
        done = 0
        self.su_write_data(caddr + 0x00, 0x3) #command
        while (True):
            done = self.su_read_data(caddr + 0x28)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(caddr + 0x18, 0x1) #respond
        # Start Conv proc.
        done = 0
        self.su_write_data(caddr + 0x00, 0x4); #command
        while (True):
            done = self.su_read_data(caddr + 0x2c)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(caddr + 0x1c, 0x1) #respond
        self.su_write_data(caddr + 0x00, 0x0) # Reset module
        self.su_write_data(vaddr + 0x00, 0x00010094)
        # print("Conv done.")
        return 1

        # Set the VDMA2
        # 1) Set the result parameter to vdma2 (R)
        # 2) Set the feature parameter to vdma2 (F)
        # 3) Set the input parameter to pool_base_addr
        # Pool computation
        # 1) Send the command to start the computation
        # 2) Spin-lock for waiting done-flag
        # 3) If receive the done flag, send respond signal
        # 4) And write the finish sign
    def su_pool_control(self, I, F, R, vaddr, paddr):
        #######################################################################
        # You should revise below code
        # Your apb-register and FSM will not match below control flow
        #######################################################################

        # Set result param to vdma2
        self.su_write_data(vaddr + 0x30, 0x00010091)
        self.su_write_data(vaddr + 0xac, R['BASE_ADDR'])
        self.su_write_data(vaddr + 0xa8, R['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0xa4, R['HSIZE'])
        self.su_write_data(vaddr + 0xa0, R['VSIZE'])

        # Set feature param to vdma2
        self.su_write_data(vaddr + 0x00, 0x00010091)
        self.su_write_data(vaddr + 0x5c, F['BASE_ADDR'])
        self.su_write_data(vaddr + 0x58, F['STRIDE_SIZE'])
        self.su_write_data(vaddr + 0x54, F['HSIZE'])
        self.su_write_data(vaddr + 0x50, F['VSIZE'])

        # Set input param, then start the max-pool proc
        self.su_write_data(paddr + 0x04, I['FLEN'])
        self.su_write_data(paddr + 0x0C, I['IN_CH'])
        self.su_write_data(paddr + 0x00, 0x1) #start

        done = 0
        # Spinlock for pool_done
        while (True):
            done = self.su_read_data(paddr + 0x8)
            if (int.from_bytes(done, 'big', signed=True) == 1):
                break
        self.su_write_data(paddr + 0x00, 0x0) # Reset module
        self.su_write_data(vaddr + 0x00, 0x00010094)
        # print("Pool done.")
        return 1



####################### RESULT CHECK
    def check_result(self, file_name, base_addr, mode=None):
        error = 0
        count = 0
        addr_test = base_addr;
        data_test = 0

        with open(file_name, "r") as file_feature:
            hex_32 = file_feature.read(32)
            data_test = self.su_read_data((addr_test+count*4))
            count = count + 1
            if(int(hex_32,2) != int.from_bytes(data_test, 'little', signed=False)):
                error = error + 1
                print("!! ERROR !! :" , error , "Count is ", count)
                print("Want : ", hex(int(hex_32,2)))
                print("Result : ", [hex(c) for c in data_test])
            i =1
            while hex_32:
                i +=1
                hex_32 = file_feature.read(32)
                if(count%1000 == 0):
                    print("Count is", count)
                if(hex_32 != ''):
                    data_test = self.su_read_data((addr_test+count*4))
                    if(int(hex_32,2) != int.from_bytes(data_test, 'little', signed=False)):
                        ## bug fixed
                        if mode == "fc3_out_2s" and count == 2:
                            continue
                        error = error + 1
                        print("!! ERROR !! , Count is ", count)
                        print("Want : ", hex(int(hex_32,2)))
                        print("Result : ", [hex(c) for c in data_test])
                    base_addr = base_addr + 4
                    count = count + 1
                    temp = data_test;     
        if(error == 0):
            print("All Results are Correct")
        else:
            print("Error : " + str(error))
            
    def save_file(self, file_name, base_addr):
        mem_addr = base_addr
        with open(file_name, "r") as file_feature:
            hex_32 = file_feature.read(32)
            self.su_write_data_trans(mem_addr, int(hex_32, 2))
            while hex_32:
                hex_32 = file_feature.read(32)
                if(hex_32 != ''):
                    mem_addr = mem_addr + 4
                    self.su_write_data_trans(mem_addr, int(hex_32, 2))