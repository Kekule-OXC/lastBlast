----------------------------------------------------------------------
---- ----
---- LPC CONTROL INTERFACE FOR Xbox Repair Chips ----
---- ----
---- maxV_chip.vhd ----
---- ----
---- ----
---- Description: ----
---- ----
---- ----
---- ----
---- Author(s): ----
---- - Aaron Van Tassle (Kekule)
----------------------------------------------------------------------

--**BANK SELECTION**
--Bank selection is controlled by the lower nibble of address REG_F70F.
--A20,A19,A18 are address lines to the parallel flash memory.
--X is not forced by the CPLD for banking purposes.
--This is how is works:
--REGISTER 0xF70F
--BANK                     IO WRITE CMD  A20|A19|A18  ADDRESS OFFSET		!!FIXME
-------------------------------------------------------------------------------------------------------
--BNKFULLTSOP              0000 0000     X  |X  |X    N/A.            
--                         XXXX 0001     1  |1  |0    0x180000         
--                         XXXX 0010     1  |0  |X    0x100000        
--BANK1 (BNK512)           XXXX 0011     0  |0  |X    0x000000
--                         XXXX 0100     0  |0  |1    0x040000
--BANK3 (BNK256)           XXXX 0101     0  |1  |0    0x080000
--BANK4 (BNKOS)            XXXX 0110     0  |1  |1    0x0C0000 --default xblast location
--                         XXXX 0111     0  |0  |X    0x000000
--                         XXXX 1000     0  |1  |X    0x080000
--                         XXXX 1001     0  |X  |X    0x000000
--                         XXXX 1010     1  |1  |1    0x1C0000
--//0xF70F write register bits configuration
--#define OSBNKCTRLBIT    	0x80u    //Bit that must be sent when selecting a flash bank other than BNKOS
--#define OSKILLMOD       	0x20u    //Completely mute modchip until a power cycle
--#define TSOPA19CTRLBIT  	0x10u    //Bit to enable manual drive of the TSOP's A19 pin.
--#define OSGROUNDD0      	0x04u    //Won't be used much here.
--#define BNKFULLTSOP     	0x00u
--#define BNKTSOPSPLIT0   	0x10u
--#define BNKTSOPSPLIT1   	0x18u
--#define NOBNKID         	0xFF

--//XBlast Mod bank toggle values
--#define BNK512  	     	0x84u
--#define BNK256  	     	0x86u
--#define BNKOS  				0x87u

--//XBlast Mod and SmartXX LPC registers to drive LCD... 
--#define XBLAST_IO    		0xF70Du
--#define XBLAST_CONTROL   0xF70Fu
--#define XODUS_CONTROL    0x00FFu
--#define LCD_DATA    		0xF700u
--#define LCD_BL        	0xF701u
--#define LCD_CT        	0xF703u
--#define XODUS_ID      	0x00FEu

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
--USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
ENTITY MAXV_CHIP IS
	PORT (
		

		LED_R : OUT STD_LOGIC:='1' ; -- R G B
		LED_G : OUT STD_LOGIC:='1' ; -- R G B
		LED_B : OUT STD_LOGIC:='1' ; -- R G B
		
		-- NOR FLASH IO
		FLASH_ADDRESS : OUT STD_LOGIC_VECTOR (20 DOWNTO 0);--:= "011000000000000000000"; -- memory address input
		FLASH_DQ : INOUT STD_LOGIC_VECTOR (7 DOWNTO 0); -- data to be transferred
		FLASH_OE : OUT STD_LOGIC; --output enable active low
		FLASH_WE : OUT STD_LOGIC; -- write enable active low
		
		-- LPC IO
		LPC_CLK : IN STD_LOGIC;
		LPC_RST : IN STD_LOGIC;
		LPC_LAD : INOUT STD_LOGIC_VECTOR (3 DOWNTO 0);
		
		control_D0	:	OUT	STD_LOGIC;
		
				
		--HD44780 LCD Pins
		LCD_OUT_DATA : OUT std_logic_vector (3 DOWNTO 0);
		LCD_RS : OUT std_logic;
		LCD_E : OUT std_logic;
		LCD_CONTRAST : OUT std_logic;
		LCD_PWM : IN STD_LOGIC
					
	);
END MAXV_CHIP;

ARCHITECTURE Behavioral OF MAXV_CHIP IS


	-- LPC BUS STATES for memory IO. Will need to include other states to
	-- support other LPC transactions.
	TYPE LPC_STATE_MACHINE IS
	(
	WAIT_START,
	CYCTYPE_DIR,
	ADDRESS,
	-- jump based on CYC_TYPE not currently implemented
	
	--WRITE
	WRITE_DATA0,
	WRITE_DATA1,
		
	--MEMORY READ
	READ_DATA0,
	READ_DATA1,

	TAR1,
	TAR2,
	--JUMP TO CORRECT POS BASED ON CYC_TYPE

	SYNC,

	--TRANSACTION CLOSE
	SYNC_COMPLETE,

	TAR_EXIT
	);
	
	TYPE CYC_TYPE IS 
	(
	IO_READ,
	IO_WRITE,
	MEM_READ,
	MEM_WRITE
	);
	
	SIGNAL LPC_CURRENT_STATE : LPC_STATE_MACHINE;
	SIGNAL CYCLE_TYPE : CYC_TYPE;
	
	SIGNAL LPC_ADDRESS : STD_LOGIC_VECTOR (20 DOWNTO 0);
	
	
	

	--IO REGISTER CONSTANTS 
	CONSTANT XBLAST_IO_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F70D";---R/W
	CONSTANT XBLAST_CONTROL_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F70F";--Write
	CONSTANT XODUS_CONTROL_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"00FF";--write
	CONSTANT LCD_BL_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F701";--"F701";--write
	CONSTANT LCD_CT_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F703";--"F703";--write
	CONSTANT LCD_DATA_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F700";--"F700";--write
	CONSTANT XODUS_ID_ADDR : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"00FE";--read		!!IMPLEMENT
	CONSTANT SYSCON_REG : STD_LOGIC_VECTOR (15 DOWNTO 0) := x"F701";--"F701";--read	
	
	
	--R/W for memory 
	SIGNAL DQ : STD_LOGIC_VECTOR (7 DOWNTO 0):= "ZZZZZZZZ";-- := (OTHERS => '0');
	--IO WRITE REGISTERS SIGNALS

--	XBLAST_IO: 0xF70D	
--W:	GPO-3	GPO-2	GPO-1	GPO-0	X		X		X			Enable 5V
--R: 	GPO-3	GPO-2	GPO-1	GPO-0	GPI-1	GPI-0	A19_ctrl	Enable 5V
--	GPO=General Purpose Output, GPO-2&3 only accessed when SW1-2 = "11" & D0_control = '1' &A19ctrl = '0'										
--	A19_ctrl = Read state of A19_ctrl. Is '1' when TSOP is split.										
--	Enable 5V = Read state of Enable 5V. Is '1' when enabled.
	SIGNAL REG_XBLAST_IO : STD_LOGIC_VECTOR (7 DOWNTO 0) := "00000000"; --GPO-3	GPO-2	GPO-1	GPO-0	GPI-1	GPI-0	A19_ctrl	Enable_5V
	
	
--	XBLAST_CONTROL: 0xF70F
--OS Bank ctrl = Seize control of iSW1 and iSW2 when set to '1'. Needs a complete power cycle to return to '0'.										
--Kill mod completely mutes modchip until a power cycle.										
--A19_ctrl enables TSOP split. Bank is selected by ltch_A19 and/or A19										
--D0_control/#A19_ctrl = This bit is set to '1' whenever D0_control = '1' OR A19_ctrl = '0'(For Evolution-X support)										
--D0_control = D0 signal is put to ground when set to '1'.										
--iSW = Internal state of SW. Is used by OS to select banks on Xblast.
--
--|Bank switches truth table | |iSW1 |iSW2 |Bank | |0 |0 |BNK512 | |0 |1 |BNK512 | |1 |0 |BNK256 | |1 |1 |BNKOS |
--|TSOP split control signals truth table | |A19_ctrl |A19 |TSOP Bank | |0 |0 |Full TSOP | |0 |1 |Full TSOP | |1 |0 |Split bank0 | |1 |1 |Split bank1 |
	SIGNAL REG_XBLAST_CONTROL : STD_LOGIC_VECTOR (7 DOWNTO 0):= "01000011"; --	X OS_Bank_ctrl	Kill_mod	A19_ctrl	A19	D0_control	iSW1	iSW2
	
--	XODUS_CONTROL 0x00FF	
--	iSW = internal state of SW. iSW can be disconnected from SW when OS seize control of it.										
--	A19_ctrl = State of TSOP split feature. '1' when TSOP split is enabled.										
--	#A19ctrl = inverted value of A19_ctrl(For Evolution-X support)										
--	D0_control/#A19_ctrl = This bit is set to '1' whenever D0_control = '1' OR A19_ctrl = '0'(For Evolution-X support)										
--	A15 = State of A15. '1' when is grounded.
--X	iSW2	A19_ctrl	iSW1	#A19_ctrl	D0_control/#A19_ctrl	A15	iSW1
	SIGNAL REG_XODUS_CONTROL : STD_LOGIC_VECTOR (7 DOWNTO 0) := "01000100"; 
	
	SIGNAL REG_LCD_BL : STD_LOGIC_VECTOR (7 DOWNTO 0);-- := "00000000"; 	--X	LCD-BL5	LCD-BL4	LCD-BL3	LCD-BL2	LCD-BL1	LCD-BL0	X
	SIGNAL REG_LCD_CT : STD_LOGIC_VECTOR (7 DOWNTO 0);-- := "00000000";	--X	LCD-CT5	LCD-CT4	LCD-CT3	LCD-CT2	LCD-CT1	LCD-CT0	X
	SIGNAL REG_LCD_DATA : STD_LOGIC_VECTOR (7 DOWNTO 0);-- := "00000000";--X	LCD-D7	LCD-D6	LCD-D5 	LCD-D4	LCD-E		LCD-RS	X  !!CHECK ME
	
--IO READ CONSTANTS
	--SIGNAL REG_XODUS_CONTROL_READ : STD_LOGIC_VECTOR (7 DOWNTO 0) := "00101010";--read		!!FIXME
	CONSTANT REG_XODUS_ID_READ : STD_LOGIC_VECTOR(7 DOWNTO 0) := "01000101"; --0x45
	SIGNAL REG_SYSCON_REG_READ : STD_LOGIC_VECTOR (7 DOWNTO 0) := "01000101";--0x45	
	SIGNAL REG_XBLAST_IO_READ : STD_LOGIC_VECTOR (7 DOWNTO 0);-- := "00000000";--	!!FIXME
	
	
	SIGNAL READBUFFER	:	STD_LOGIC_VECTOR (7 DOWNTO 0);
	SIGNAL reset : STD_LOGIC :='0';
	SIGNAL CONTRAST_TARGET : STD_LOGIC:='0';
	SIGNAL pos : STD_LOGIC_VECTOR(6 DOWNTO 0) := "0000000";
	
	--GENERAL COUNTER USED TO TRACK ADDRESS AND SYNC STATES.
	SIGNAL COUNT : INTEGER RANGE 0 to 7;
	
	
BEGIN

	LED_R <= LPC_ADDRESS(20);--REG_XBLAST_CONTROL(7);
	LED_G <= LPC_ADDRESS(19);--REG_XBLAST_CONTROL(1);
	LED_B <= LPC_ADDRESS(18);--REG_XBLAST_CONTROL(0);


	LCD_CONTRAST<=CONTRAST_TARGET;

	-- Connections for LCD transaction
	--LCD Data has this format
	--X,D6,D7,D4,D5,E,RS,X in that order. See Ref 2.
	LCD_RS <= REG_LCD_DATA(1);
	LCD_E <= REG_LCD_DATA(2);
	LCD_OUT_DATA(0) <= REG_LCD_DATA(4);
	LCD_OUT_DATA(1) <= REG_LCD_DATA(3);
	LCD_OUT_DATA(2) <= REG_LCD_DATA(6);
	LCD_OUT_DATA(3) <= REG_LCD_DATA(5);
	
	 
	
	FLASH_ADDRESS <= LPC_ADDRESS;
	 
	 
	

--	--Generate signal for PWM on LCD
PW : entity work.pwm port map(LPC_CLK,reset, pos, CONTRAST_TARGET);

		
		--LAD lines can be either input or output
		--The output values depend on variable states of the LPC transaction!
		LPC_LAD <= "0000" WHEN LPC_CURRENT_STATE = SYNC_COMPLETE ELSE
		           "0101" WHEN LPC_CURRENT_STATE = SYNC ELSE
		           "1111" WHEN LPC_CURRENT_STATE = TAR2  ELSE
		           "1111" WHEN LPC_CURRENT_STATE = TAR_EXIT ELSE
						READBUFFER(3 DOWNTO 0) WHEN LPC_CURRENT_STATE = READ_DATA0 ELSE 
						READBUFFER(7 DOWNTO 4) WHEN LPC_CURRENT_STATE = READ_DATA1 ELSE 
						"ZZZZ";
		--Flash data vector outputs the data value in MEM_WRITE mode, else its just an input
		FLASH_DQ <= DQ WHEN CYCLE_TYPE = MEM_WRITE ELSE "ZZZZZZZZ";
		
		--Active low signals, Write Enable and Output Enable for Flash Memory Write and Reads respectively.
		--FLASH_WE <= '0' WHEN CYCLE_TYPE = MEM_WRITE ELSE '1';
		FLASH_WE <= '0' WHEN CYCLE_TYPE = MEM_WRITE AND
               (LPC_CURRENT_STATE = TAR1 OR
               LPC_CURRENT_STATE = TAR2 OR
               LPC_CURRENT_STATE = SYNC) ELSE '1';

		--Output Enable for Flash Memory Read (Active low)
		--Output Enable must be pulled low for 50ns before data is valid for reading
		FLASH_OE <= '0' WHEN CYCLE_TYPE = MEM_READ AND
               (LPC_CURRENT_STATE = TAR1 OR
               LPC_CURRENT_STATE = TAR2 OR
               LPC_CURRENT_STATE = SYNC OR
               LPC_CURRENT_STATE = SYNC_COMPLETE OR
               LPC_CURRENT_STATE = READ_DATA0 OR
               LPC_CURRENT_STATE = READ_DATA1 OR
               LPC_CURRENT_STATE = TAR_EXIT) ELSE '1';


		--D0 recreates LFRAME. This is required for a 1.6
		--control_D0 <= '0' WHEN (LPC_LAD = "0000" AND LPC_CURRENT_STATE = WAIT_START) ELSE 'Z';
		
		-- LPC Device State machine, see the Intel LPC Specifications for details
		PROCESS (LPC_RST, LPC_CLK) BEGIN
		
		IF (LPC_RST = '0') THEN  --initalize values
			--LCD_DATA_BYTE <= "00000000";
			--LCD_ADDRESS <= "0000000000000000";
			--PWM_COUNT_CONTRAST <= "0000";
			--LCD_CONTRAST_NIBBLE <= "1100";

			
			LPC_CURRENT_STATE <= WAIT_START;
			CYCLE_TYPE <= IO_READ;
			
		ELSIF (rising_edge(LPC_CLK)) THEN
		
			CASE LPC_CURRENT_STATE IS
			
				WHEN WAIT_START =>
					IF LPC_LAD = "0000" THEN --indicates start of cycle for memory IO and DMA cycles, and indicates LFRAME on 1.3+
						LPC_CURRENT_STATE <= CYCTYPE_DIR;
					END IF;
					
				WHEN CYCTYPE_DIR => --determine transaction type
					IF LPC_LAD(3 DOWNTO 1) = "000" THEN
						CYCLE_TYPE <= IO_READ;
						COUNT <=3;
						LPC_CURRENT_STATE <= ADDRESS;
					ELSIF LPC_LAD(3 DOWNTO 1) = "001" THEN
						CYCLE_TYPE <= IO_WRITE;
						COUNT<=3;
						LPC_CURRENT_STATE <= ADDRESS;
					ELSIF LPC_LAD(3 DOWNTO 1) = "010" THEN
						CYCLE_TYPE <= MEM_READ;
						COUNT<=7; 
						LPC_CURRENT_STATE <= ADDRESS;
					ELSIF LPC_LAD(3 DOWNTO 1) = "011" THEN
						CYCLE_TYPE <= MEM_WRITE;
						COUNT<=7;
						LPC_CURRENT_STATE <= ADDRESS;
					ELSE
						LPC_CURRENT_STATE <= WAIT_START; -- Unsupported, reset state machine.
					END IF;
					
				WHEN ADDRESS => 
					IF COUNT = 5 THEN
						LPC_ADDRESS(20) <= LPC_LAD(0);
						
					ELSIF COUNT = 4 THEN
						LPC_ADDRESS(19 DOWNTO 16) <= LPC_LAD;
						--BANK CONTROL
						CASE REG_XBLAST_CONTROL(1 DOWNTO 0) IS --this skips 00 which is another BNK512
							WHEN "00" => 
								LPC_ADDRESS(20 DOWNTO 19) <= "00"; --BNK512 
							WHEN "10" => 
								LPC_ADDRESS(20 DOWNTO 18) <= "010"; --BNK256
							WHEN "11" => 
								LPC_ADDRESS(20 DOWNTO 18) <= "011"; --BNKOS
							WHEN "01" =>
								LPC_CURRENT_STATE <= WAIT_START;
								--control_D0<='1';
							WHEN OTHERS => 	
						END CASE;
				
					ELSIF COUNT = 3 THEN
						LPC_ADDRESS(15 DOWNTO 12) <= LPC_LAD;
					
					ELSIF COUNT = 2 THEN
						LPC_ADDRESS(11 DOWNTO 8) <= LPC_LAD;
					
					ELSIF COUNT = 1 THEN
						LPC_ADDRESS(7 DOWNTO 4) <= LPC_LAD;
						
					ELSIF COUNT = 0 THEN
						LPC_ADDRESS(3 DOWNTO 0) <= LPC_LAD;
						IF CYCLE_TYPE = IO_READ OR CYCLE_TYPE = MEM_READ THEN
							LPC_CURRENT_STATE <= TAR1;
						ELSIF CYCLE_TYPE = IO_WRITE OR CYCLE_TYPE = MEM_WRITE THEN
							LPC_CURRENT_STATE <= WRITE_DATA0;
						END IF;
					END IF;
					COUNT <= COUNT - 1;	
				
				--WRITE DATA
				WHEN WRITE_DATA0 => 
					IF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XBLAST_CONTROL_ADDR THEN
						REG_XBLAST_CONTROL(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XBLAST_IO_ADDR THEN
						REG_XBLAST_IO(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XODUS_CONTROL_ADDR THEN
						REG_XODUS_CONTROL(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_BL_ADDR THEN
						REG_LCD_BL(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_CT_ADDR THEN
						REG_LCD_CT(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_DATA_ADDR THEN
						REG_LCD_DATA(3 DOWNTO 0) <= LPC_LAD;
					ELSIF CYCLE_TYPE = MEM_WRITE THEN
						DQ(3 DOWNTO 0) <= LPC_LAD;
					END IF;
					LPC_CURRENT_STATE <= WRITE_DATA1;
					
				WHEN WRITE_DATA1 => 
					IF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XBLAST_CONTROL_ADDR THEN
						REG_XBLAST_CONTROL(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XBLAST_IO_ADDR THEN
						REG_XBLAST_IO(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = XODUS_CONTROL_ADDR THEN
						REG_XODUS_CONTROL(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_BL_ADDR THEN
						REG_LCD_BL(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_CT_ADDR THEN
						REG_LCD_CT(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = IO_WRITE AND LPC_ADDRESS(15 DOWNTO 0) = LCD_DATA_ADDR THEN
						REG_LCD_DATA(7 DOWNTO 4) <= LPC_LAD;
					ELSIF CYCLE_TYPE = MEM_WRITE THEN	
						DQ(7 DOWNTO 4) <= LPC_LAD;
					END IF;
				LPC_CURRENT_STATE <= TAR1;
				
				
				--READ DATA		
				WHEN READ_DATA0 =>
					LPC_CURRENT_STATE <= READ_DATA1;					
				WHEN READ_DATA1 =>
					LPC_CURRENT_STATE <= TAR_EXIT;
					
				--TURN AROUND
				WHEN TAR1 => 
					LPC_CURRENT_STATE <= TAR2;
				WHEN TAR2 => 
					LPC_CURRENT_STATE <= SYNC;
					IF CYCLE_TYPE = MEM_READ THEN
						COUNT <= 2;-- 6; 
					ELSIF CYCLE_TYPE = IO_READ THEN
						COUNT <= 6;
					END IF;

				WHEN SYNC =>
					COUNT <= COUNT - 1;--always does COUNT+1 sync cycles
					--Buffer IO reads during syncing. Helps output timings
					IF COUNT = 1 THEN
						IF CYCLE_TYPE = MEM_READ THEN
							READBUFFER <= FLASH_DQ;
						ELSIF CYCLE_TYPE = IO_READ THEN
							IF LPC_ADDRESS(15 DOWNTO 0) = XBLAST_IO_ADDR THEN
								READBUFFER <= REG_XBLAST_IO_READ;
							ELSIF LPC_ADDRESS(15 DOWNTO 0) = SYSCON_REG THEN
								READBUFFER <= REG_SYSCON_REG_READ;
							ELSIF LPC_ADDRESS(15 DOWNTO 0) = XODUS_ID_ADDR THEN
								READBUFFER <= REG_XODUS_ID_READ;
							ELSE
								READBUFFER <= "11111111";
							END IF;
						END IF;
					ELSIF COUNT = 0 THEN
						LPC_CURRENT_STATE <= SYNC_COMPLETE;
					END IF;

				WHEN SYNC_COMPLETE => 
            IF CYCLE_TYPE = MEM_READ OR CYCLE_TYPE = IO_READ THEN
               LPC_CURRENT_STATE <= READ_DATA0;
            ELSE
               LPC_CURRENT_STATE <= TAR_EXIT;
            END IF;
					
					
						--TURN BUS AROUND (PERIPHERAL TO HOST)
						
				WHEN TAR_EXIT => 
					--D0 is held low until a few memory reads
					--This ensures it is booting from the modchip.
					--Releases after 5 reads.
					IF LPC_ADDRESS(7 DOWNTO 0) = x"74" THEN
						control_D0 <= '0';
					END IF;
					CYCLE_TYPE <= IO_READ;
					LPC_CURRENT_STATE <= WAIT_START;
					
				
			END CASE;
		END IF;
		END PROCESS;


END Behavioral;

