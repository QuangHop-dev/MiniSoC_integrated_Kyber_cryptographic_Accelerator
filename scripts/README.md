# Scripts

Các script trong thư mục này là entry point chính cho build firmware, mô phỏng, tạo bitstream và chạy demo trên ZCU102. Output sinh tự động được ghi vào `build/` hoặc `sw/build/`.

## Firmware

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_firmware.ps1 -App kyber_demo
powershell -ExecutionPolicy Bypass -File scripts\build_uart_bootloader.ps1
powershell -ExecutionPolicy Bypass -File scripts\build_uart_payload.ps1 -App full_demo -Target imem
```

## Simulation

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_all_tests.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_kyber_wb_slave_kat_tb.ps1 -Tests 100 -BatchSize 100
powershell -ExecutionPolicy Bypass -File scripts\run_soc_top_tb.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_soc_top_uart_bootloader_tb.ps1
```

## ZCU102

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_vivado_zcu102.ps1 -CreateOnly
powershell -ExecutionPolicy Bypass -File scripts\build_vivado_zcu102.ps1 -Bootloader -Jobs 4
powershell -ExecutionPolicy Bypass -File scripts\program_zcu102.ps1 -Bitstream build\vivado\zcu102\kyber_soc_zcu102.bit
```

## UART payload

```bat
scripts\send_uart_payload.cmd -Port COM5 -Target imem -Baud 115200
scripts\run_firmware_gui.cmd
```

Nếu tool không nằm trong `PATH`, truyền đường dẫn qua các tham số như `-Cross`, `-Vivado`, `-Python` hoặc `-Make`.

`scripts/lib/soc_flow.ps1` chứa các hàm dùng chung cho tìm tool, build firmware, compile RTL và kiểm tra PASS/FAIL log mô phỏng.
