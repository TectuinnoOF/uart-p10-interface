# P10-Link — Interfaz UART → Panel LED P10 (ASIC/FPGA)

**P10-Link** es un núcleo digital 100% **Verilog‑2001** para recibir datos por **UART** y controlar directamente un **panel LED P10 (1/4 scan)**. Implementa recepción a **115200 bps (8N1)**, doble buffer de imagen y una FSM de display que genera **OE, A, B, LAT, SRCLK y SER**. Validado funcionalmente en **Tang Nano 9K @ 27 MHz**; listo para integrar en **ASIC** (oblea compartida).

> Nota: actualmente **no hay testbench formal**. Las pruebas se realizaron en FPGA y el funcionamiento es estable.

---

## Características

* UART asíncrono **115200 bps (8N1)**; `CLK_FRE=27 MHz` (parámetro de síntesis).
* **Trama de 64 bytes** por actualización: 4 filas × 16 bytes/ﬁla.
* **Doble buffer (128 bytes)**: Banco A (recibido) → Banco B (activo) en cuanto la trama se completa.
* **Timeout** de recepción: **2 000 000** ciclos (\~**74 ms** @ 27 MHz) → reinicio seguro.
* **Control de panel P10 (1/4 scan)** con señales: **OE, A, B, LAT, SRCLK, SER**.
* **Indicador de estado (`led`)**: encendido = error/sin datos; apagado = trama válida.
* 3.3 V CMOS I/O (no tolerante a 5 V).

---

## Especificaciones rápidas

| Parámetro         |                     Valor | Comentario                                      |
| ----------------- | ------------------------: | ----------------------------------------------- |
| Reloj del sistema |                    27 MHz | Fijo en RTL actual (parametrizable en síntesis) |
| UART              |          115200 bps (8N1) | Sin paridad, 1 bit de stop                      |
| Longitud de trama |                  64 bytes | 4×(16 bytes/ﬁla)                                |
| Buffer interno    |                 128 bytes | Banco A (RX) + Banco B (activo)                 |
| Timeout RX        |                   \~74 ms | 2 000 000 ciclos @ 27 MHz                       |
| Panel             |             P10, 1/4 scan | Resolución objetivo **64×16**                   |
| Señales a panel   | OE, A, B, LAT, SRCLK, SER | Salidas                                         |
| Indicador         |                     `led` | Estado de trama                                 |

> El mapeo de bits hacia el panel puede variar según el fabricante del P10/cableado. El core desplaza **128 bits por selección de fila** (16 bytes).

---

## Pines / Señales

| Señal    | Dir | Descripción                                |
| -------- | --- | ------------------------------------------ |
| `clk`    | In  | Reloj del sistema (27 MHz)                 |
| `rst`    | In  | Reset global activo en bajo                |
| `rx_pin` | In  | Entrada UART (RX)                          |
| `OE`     | Out | Output Enable del panel                    |
| `A`, `B` | Out | Selección de fila (1/4 scan)               |
| `SRCLK`  | Out | Reloj de desplazamiento (shift clock)      |
| `LAT`    | Out | Latch de datos hacia los drivers del panel |
| `SER`    | Out | Datos en serie hacia el panel              |
| `led`    | Out | Indicador de estado (0 = trama válida)     |

---

## Formato de trama UART

* Total **64 bytes** por actualización de pantalla.
* Orden: **Fila 0 → Fila 1 → Fila 2 → Fila 3**, cada una con **16 bytes**.
* Al completar los 64 bytes sin **timeout**, el Banco A se copia a Banco B y la FSM comienza a refrescar.

> **Timeout (\~74 ms)** si la trama queda incompleta; el core descarta y espera una nueva.

---

## Integración (snippet Verilog)

```verilog
// Top-level example: pure Verilog-2001 (comments in English)
module top (
    input  clk,
    input  rst,
    input  rx_pin,
    output OE, A, B, SRCLK, LAT, SER,
    output led
);
  wire [7:0] dato_uart;
  wire       rx_data_valid;
  wire       rx_data_ready;

  assign rx_data_ready = 1'b1; // Always ready to accept a new byte

  uart_rx u_rx (
    .clk(clk), .rst(rst),
    .rx_pin(rx_pin),
    .rx_data(dato_uart),
    .rx_data_ready(rx_data_ready),
    .rx_data_valid(rx_data_valid)
  );

  display u_disp (
    .clk(clk), .rst(rst),
    .rx_data_valid(rx_data_valid),
    .dato_uart(dato_uart),
    .OE(OE), .A(A), .B(B), .SRCLK(SRCLK), .LAT(LAT), .SER(SER),
    .led(led)
  );
endmodule
```

---

## Conexión típica (hardware)

1. **Alimentación 3.3 V** regulada y desacoplada cerca del ASIC/FPGA.
2. **UART RX** desde PC/MCU (USB‑TTL a 3.3 V). Si usas RS‑485, adapta con transceptor externo.
3. Conecta al panel P10: **OE, A, B, LAT, SRCLK, SER**.
4. Opcional: LED de estado a `led` (con resistencia serie).

> **No tolerante a 5 V**. Usa adaptadores de nivel si tu host es 5 V.

---

## Ejemplo de envío (host)

```python
# Python 3 + pyserial — send one 64-byte frame
# Each row has 16 bytes (LSB-first bit shift at the panel side)
import serial
frame = bytearray(64)
# TODO: fill 'frame' with your row data (row0[16] + row1[16] + row2[16] + row3[16])
with serial.Serial('COM3', 115200, timeout=1) as s:
    s.write(frame)
```

---

## Estado del proyecto

* **FPGA (Tang Nano 9K)**: probado estable @ 27 MHz / 115200 bps.
* **ASIC (oblea compartida)**: listo para envío; generar *views*/constraints según flujo.
* **Testbench**: pendiente (no incluido actualmente).

---

## Estructura sugerida del repositorio

```
p10-link/
├─ rtl/           # Verilog 2001: uart_rx.v, display.v, top.v
├─ doc/           # Datasheet, diagramas, notas
├─ examples/      # Scripts de envío UART, patrones de imagen
├─ fpga/          # Top y constraints para validación en Tang Nano 9K
└─ LICENSE
```

---

## Licencia

Elige la que prefieras (MIT/BSD/Apache‑2.0). Incluye el archivo `LICENSE`.

---

## Créditos

Proyecto **Tectuino** — Interfaz **P10‑Link** (UART → P10).
Equipo: *\[tu equipo]* · Contacto: *\[tu correo]*
