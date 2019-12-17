-- https://www.codeproject.com/Articles/513169/Servomotor-Control-with-PWM-and-VHDL
--https://www.digikey.com/eewiki/pages/viewpage.action?pageId=20939345&utm_adgroup=General&slid=&gclid=CjwKCAjwq4fsBRBnEiwANTahcFA1h-_3RCxEktKPKAfM_SAfjySeEVaQF4_AvyJxJqgoLXcbCN69nxoCjdEQAvD_BwE


LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_ARITH.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pwm is
    PORT (
        clk   : IN  STD_LOGIC;
        reset : IN  STD_LOGIC;
        pos   : IN  STD_LOGIC_VECTOR(6 downto 0);
        contrast : OUT STD_LOGIC
    );
end pwm;

architecture Behavioral of pwm is
    -- Counter, from 0 to 1279.
    signal cnt : unsigned(10 downto 0);
    -- Temporal signal used to generate the PWM pulse.
    signal pwmi: unsigned(7 downto 0);
begin
    -- Minimum value should be 0.5ms.
    pwmi <= unsigned('0' & pos) + 32;
    -- Counter process, from 0 to 1279.
    counter: process (reset, clk) begin
        if (reset = '1') then
            cnt <= (others => '0');
        elsif rising_edge(clk) then
            if (cnt = 1279) then
                cnt <= (others => '0');
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;
    -- Output signal for the servomotor.
    contrast <= '1' when (cnt < pwmi) else '0';
end Behavioral;
