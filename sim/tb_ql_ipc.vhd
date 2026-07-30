library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ql_ipc is
end entity;

architecture test of tb_ql_ipc is
  signal clk : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal ce_accum : unsigned(15 downto 0) := (others => '0');
  signal xtal_en : std_logic := '0';
  signal comdata_in : std_logic;
  signal comctrl : std_logic;
  signal p1_out : std_logic_vector(7 downto 0);
  signal p2_in : std_logic_vector(7 downto 0);
  signal p2_out : std_logic_vector(7 downto 0);
  signal keyboard_matrix : std_logic_vector(63 downto 0) := (others => '0');
  signal keyboard_data : std_logic_vector(7 downto 0);
  signal comctrl_falls : natural := 0;
  signal host_shift : std_logic_vector(3 downto 0) := (others => '1');
  signal host_busy : natural range 0 to 2 := 0;
  signal host_load : std_logic := '0';
  signal host_bit : std_logic := '0';
  signal keyboard_row_seen : std_logic := '0';
begin
  clk <= not clk after 15.625 ns;

  process(clk)
    variable total : unsigned(16 downto 0);
  begin
    if rising_edge(clk) then
      total := ('0' & ce_accum) + to_unsigned(22667, 17);
      ce_accum <= total(15 downto 0);
      xtal_en <= total(16);
    end if;
  end process;

  keyboard_data <=
    keyboard_matrix(7 downto 0) when p1_out(0) = '1' else
    keyboard_matrix(15 downto 8) when p1_out(1) = '1' else
    keyboard_matrix(23 downto 16) when p1_out(2) = '1' else
    keyboard_matrix(31 downto 24) when p1_out(3) = '1' else
    keyboard_matrix(39 downto 32) when p1_out(4) = '1' else
    keyboard_matrix(47 downto 40) when p1_out(5) = '1' else
    keyboard_matrix(55 downto 48) when p1_out(6) = '1' else
    keyboard_matrix(63 downto 56) when p1_out(7) = '1' else
    x"00";

  p2_in <= (7 => p2_out(7) and comdata_in, others => '0');
  comdata_in <= host_shift(0);

  ipc_cpu : entity work.t8049_notri
    generic map (gate_port_input_g => 0)
    port map (
      xtal_i => clk, xtal_en_i => xtal_en, reset_n_i => reset_n,
      t0_i => '0', t0_o => open, t0_dir_o => open,
      int_n_i => '1', ea_i => '0', rd_n_o => open,
      psen_n_o => open, wr_n_o => comctrl, ale_o => open,
      db_i => keyboard_data, db_o => open, db_dir_o => open,
      t1_i => '0', p2_i => p2_in, p2_o => p2_out,
      p2l_low_imp_o => open, p2h_low_imp_o => open,
      p1_i => x"00", p1_o => p1_out, p1_low_imp_o => open,
      prog_n_o => open,
      rom_we_i => '0', rom_waddr_i => (others => '0'),
      rom_wdata_i => (others => '0')
    );

  process(clk)
    variable previous_comctrl : std_logic := '1';
  begin
    if rising_edge(clk) then
      if host_load = '1' then
        host_shift <= "11" & host_bit & '0';
        host_busy <= 2;
      elsif comctrl = '0' and previous_comctrl = '1' then
        host_shift <= '1' & host_shift(3 downto 1);
        comctrl_falls <= comctrl_falls + 1;
        if host_busy /= 0 then
          host_busy <= host_busy - 1;
        end if;
      end if;
      if keyboard_matrix(37) = '1' and p1_out(4) = '1' and
         keyboard_data(5) = '1' then
        keyboard_row_seen <= '1';
      end if;
      previous_comctrl := comctrl;
    end if;
  end process;

  process
  begin
    wait for 2 us;
    reset_n <= '1';
    wait for 5 ms;
    report "IPC idle P1=" & to_hstring(p1_out) &
           " P2=" & to_hstring(p2_out) &
           " COMCTRL falls=" & integer'image(comctrl_falls);
    assert p2_out(3 downto 2) = "11"
      report "IPC IPL outputs are not inactive after reset" severity failure;
    keyboard_matrix(37) <= '1';

    -- QDOS sends IPC command 8 most-significant bit first. Each bit is
    -- framed as start, data, stop, extra stop by the ZX8302 shift register.
    host_bit <= '1'; host_load <= '1'; wait until rising_edge(clk);
    host_load <= '0'; wait until host_busy = 0 for 1 ms;
    assert host_busy = 0 report "IPC did not clock command bit 1" severity failure;
    host_bit <= '0'; host_load <= '1'; wait until rising_edge(clk);
    host_load <= '0'; wait until host_busy = 0 for 1 ms;
    assert host_busy = 0 report "IPC did not clock command bit 2" severity failure;
    host_bit <= '0'; host_load <= '1'; wait until rising_edge(clk);
    host_load <= '0'; wait until host_busy = 0 for 1 ms;
    assert host_busy = 0 report "IPC did not clock command bit 3" severity failure;
    host_bit <= '0'; host_load <= '1'; wait until rising_edge(clk);
    host_load <= '0'; wait until host_busy = 0 for 1 ms;
    assert host_busy = 0 report "IPC did not clock command bit 4" severity failure;

    wait for 2 ms;
    report "IPC command response P1=" & to_hstring(p1_out) &
           " P2=" & to_hstring(p2_out) &
           " COMCTRL falls=" & integer'image(comctrl_falls);
    assert comctrl_falls >= 8
      report "IPC did not service the serial command" severity failure;
    assert keyboard_row_seen = '1'
      report "IPC did not scan the asserted QL keyboard row" severity failure;
    report "PASS: 8049 firmware, IPL, serial link, and keyboard scan";
    std.env.finish;
  end process;
end architecture;
