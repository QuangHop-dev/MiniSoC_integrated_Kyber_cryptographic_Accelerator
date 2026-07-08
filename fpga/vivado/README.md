# Vivado flow for ZCU102

Thư mục này chứa Tcl flow để tạo project, chạy synthesis/implementation và copy bitstream cuối cho thiết kế Kyber-512 RISC-V SoC trên ZCU102 PL.

## Entry points

Từ thư mục gốc repository:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_vivado_zcu102.ps1 -CreateOnly
```

Build bitstream thường:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_vivado_zcu102.ps1 -Jobs 4
```

Build bitstream bootloader mode:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_vivado_zcu102.ps1 -Bootloader -Jobs 4
```

Bootloader mode nhúng firmware `sw/apps/uart_bootloader` vào Boot ROM và dành vùng `0x00004000..0x00007fff` làm IMEM writable để nhận payload qua UART.

## Files

- `create_project.tcl`: tạo project, đọc RTL, đọc XDC và cấu hình generic.
- `build_bitstream.tcl`: chạy synth/impl/write_bitstream và copy file `.bit` ra output directory.
- `program_bitstream.tcl`: nạp bitstream qua hardware manager.
- `report_hier_util.tcl`: helper report utilization theo hierarchy.
- `constraints/zcu102_pl_only.xdc`: clock, reset, UART, LED, DIP switch, push button và I2C pin mapping.
