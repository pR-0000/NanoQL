library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

architecture sim of t49_rom is
  type rom_t is array (0 to 2047) of std_logic_vector(7 downto 0);

  impure function load_rom return rom_t is
    file source : text open read_mode is "src/ipc/ql_ipc_rom.hex";
    variable line_data : line;
    variable contents : rom_t := (others => x"FF");
  begin
    for index in contents'range loop
      exit when endfile(source);
      readline(source, line_data);
      hread(line_data, contents(index));
    end loop;
    return contents;
  end function;

  signal contents : rom_t := load_rom;
begin
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rom_we_i = '1' then
        contents(to_integer(unsigned(rom_waddr_i))) <= rom_wdata_i;
      end if;
      rom_data_o <= contents(to_integer(unsigned(rom_addr_i)));
    end if;
  end process;
end sim;
