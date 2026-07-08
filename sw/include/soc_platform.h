#ifndef SOC_PLATFORM_H
#define SOC_PLATFORM_H

#define SOC_CPU_HZ             166666667u
#define SOC_UART_BAUD          115200u
#define SOC_UART_DIV           (SOC_CPU_HZ / (16u * SOC_UART_BAUD))
#define SOC_KYBER_TIMEOUT      SOC_CPU_HZ

#define SOC_DEMO_BOOT_MARK     0x01u
#define SOC_DEMO_KEYGEN_MARK   0x11u
#define SOC_DEMO_ENCAPS_MARK   0x22u
#define SOC_DEMO_DECAPS_MARK   0x33u
#define SOC_DEMO_REJECT_MARK   0x44u
#define SOC_DEMO_DONE_MARK     0xA5u

#define SOC_DEMO_ERR_KEYGEN    0xE1u
#define SOC_DEMO_ERR_ENCAPS    0xE2u
#define SOC_DEMO_ERR_DECAPS    0xE3u
#define SOC_DEMO_ERR_COMPARE   0xE4u
#define SOC_DEMO_ERR_REJECT    0xE5u

#endif
