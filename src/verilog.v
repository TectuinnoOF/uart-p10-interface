/// sta-blackbox

module TCT_UARTP10 (
`ifdef USE_POWER_PINS
    inout  wire vccd1, // 1.8V power
    inout  wire vssd1, // ground
`endif
    input  clk,
    input  rst,
    input  rx_pin,
    output OE,
    output A,
    output B,
    output SRCLK,
    output LAT,
    output SER,
    output led
);    

    wire [7:0] dato_uart;
    wire rx_data_ready;
    wire rx_data_valid;

    // siempre listo para recibir
    assign rx_data_ready = 1'b1;

    // Instancia del receptor UART
    uart_rx u1 (
        .clk(clk),
        .rst(rst),
        .rx_data(dato_uart),
        .rx_data_ready(rx_data_ready),
        .rx_pin(rx_pin),
        .rx_data_valid(rx_data_valid)
    );

    // Instancia del controlador del display
    display u2 (
        .clk(clk),
        .rst(rst),
        .rx_data_valid(rx_data_valid),
        .dato_uart(dato_uart),
        .OE(OE),
        .A(A),
        .B(B),
        .SRCLK(SRCLK),
        .LAT(LAT),
        .SER(SER),
        .led(led)
    );

endmodule

module display (
    input  clk,                  // Reloj del sistema
    input  rst,                  // Reset global (activo en bajo)
    input  rx_data_valid,        // Señal que indica nuevo byte UART disponible
    input  [7:0] dato_uart,      // Byte recibido por UART

    output reg OE,               // Habilita salida del display
    output reg A, B,             // Selección de fila activa (2 bits)
    output SRCLK,                // Reloj serial para envío de bits
    output reg LAT,              // Latch para capturar datos en el registro de salida
    output reg SER,              // Línea de datos seriales
    output reg led               // LED de estado (indicador visual)
);

    // Estados de la máquina de estados
    reg [2:0] state, nextstate;

    // Divisor de frecuencia para generar pulsos más lentos
    reg [3:0] div;
    reg pulsito;

    // Variables de control
    reg [7:0]   conta_tx;        // Contador de bits transmitidos (hasta 128)
    reg [8:0]   conta_oe;        // Contador de tiempo de habilitación de salida
    reg [127:0] reg_ser;         // Registro de desplazamiento de 128 bits
    reg [1:0]   fila_cnt;        // Fila activa
    reg [6:0]   cnt_rx;          // Contador de bytes recibidos
    reg         valid_frame;     // Frame válido recibido
    reg         srclk_en;        // Habilita SRCLK

    // Temporizador para timeout
    reg [20:0] frame_timer;
    reg timeout_frame;

    // Memoria del display (128 bytes = 64 datos + backup)
    reg [7:0] display_mem [0:127];

    reg fin_64;

    integer i;

    // ---------- ENSAMBLA FILA SIN PART-SELECT VARIABLE ----------
    reg [7:0]  b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13,b14,b15;
    reg [127:0] row_data;

    always @(*) begin
        // Lee 16 bytes contiguos según fila_cnt
        b0  = display_mem[64 + (fila_cnt*16) +  0];
        b1  = display_mem[64 + (fila_cnt*16) +  1];
        b2  = display_mem[64 + (fila_cnt*16) +  2];
        b3  = display_mem[64 + (fila_cnt*16) +  3];
        b4  = display_mem[64 + (fila_cnt*16) +  4];
        b5  = display_mem[64 + (fila_cnt*16) +  5];
        b6  = display_mem[64 + (fila_cnt*16) +  6];
        b7  = display_mem[64 + (fila_cnt*16) +  7];
        b8  = display_mem[64 + (fila_cnt*16) +  8];
        b9  = display_mem[64 + (fila_cnt*16) +  9];
        b10 = display_mem[64 + (fila_cnt*16) + 10];
        b11 = display_mem[64 + (fila_cnt*16) + 11];
        b12 = display_mem[64 + (fila_cnt*16) + 12];
        b13 = display_mem[64 + (fila_cnt*16) + 13];
        b14 = display_mem[64 + (fila_cnt*16) + 14];
        b15 = display_mem[64 + (fila_cnt*16) + 15];

        // Empaqueta a 128 bits (constante, sin índices variables)
        row_data = { b15,b14,b13,b12,b11,b10,b9,b8,b7,b6,b5,b4,b3,b2,b1,b0 };
    end
    // ------------------------------------------------------------

    // Temporizador de timeout en recepción
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            frame_timer   <= 0;
            timeout_frame <= 0;
        end else if (rx_data_valid) begin
            frame_timer   <= 0;
            timeout_frame <= 0;
        end else if (cnt_rx != 0) begin
            if (frame_timer == 21'd2000000)
                timeout_frame <= 1;
            else
                frame_timer <= frame_timer + 1;
        end else begin
            frame_timer   <= 0;
            timeout_frame <= 0;
        end
    end
    

    // Captura de datos UART
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (i = 0; i < 128; i = i + 1) begin
                display_mem[i] = 8'd0;
            end
            cnt_rx      <= 0;
            valid_frame <= 0;
            led         <= 1;
            fin_64      <= 0;
        end else if (rx_data_valid) begin
            if (cnt_rx < 64) begin
                display_mem[cnt_rx] <= dato_uart;
                cnt_rx <= cnt_rx + 1;
            end
            fin_64 <= 0;
        end else if (cnt_rx == 64 && !timeout_frame) begin
            for (i = 0; i < 64; i = i + 1)
                display_mem[i + 64] <= display_mem[i];
            valid_frame <= 1;
            led         <= 0;
            cnt_rx      <= 0;
            fin_64      <= 1;
        end else if ((cnt_rx > 64) || timeout_frame) begin
            valid_frame <= 0;
            led         <= 1;
            cnt_rx      <= 0;
            fin_64      <= 0;
        end else begin
            fin_64 <= 0;
        end
    end

    // Divisor de frecuencia
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            div     <= 0;
            pulsito <= 0;
        end else if (div == 4'd13) begin
            div     <= 0;
            pulsito <= ~pulsito;
        end else begin
            div <= div + 1;
        end
    end

    // Generación de reloj serial
    assign SRCLK = srclk_en ? ~pulsito : 1'b0;

    // Registro de estado
    always @(posedge pulsito or negedge rst) begin
        if (!rst)
            state <= 3'd0;
        else
            state <= nextstate;
    end

    // Lógica de transición de estados
    always @(*) begin
        nextstate = state;
        case (state)
            3'd0: nextstate = 3'd1;
            3'd1: nextstate = (conta_tx < 128) ? 3'd1 : 3'd2;
            3'd2: nextstate = 3'd3;
            3'd3: nextstate = (conta_oe < 9'd382) ? 3'd3 : 3'd4;
            3'd4: nextstate = 3'd1;
            default: nextstate = 3'd0;
        endcase
    end

    // FSM de control del display
    always @(posedge pulsito or negedge rst) begin
        if (!rst) begin
            conta_tx  <= 0;
            conta_oe  <= 0;
            reg_ser   <= 128'd0;
            fila_cnt  <= 0;
            A         <= 0;
            B         <= 0;
            OE        <= 0;
            LAT       <= 0;
            SER       <= 0;
            srclk_en  <= 0;
        end else begin
            case (state)
                3'd0: begin // Reset
                    conta_tx  <= 0;
                    conta_oe  <= 0;
                    reg_ser   <= 128'd0;
                    fila_cnt  <= 0;
                    A         <= 0;
                    B         <= 0;
                    OE        <= 0;
                    LAT       <= 0;
                    SER       <= 0;
                    srclk_en  <= 0;
                end
                3'd1: begin // Envío serial de 128 bits
                    if (conta_tx < 8'd128) begin
                        SER       <= ~reg_ser[127];
                        reg_ser   <= {reg_ser[126:0], 1'b0};
                        conta_tx  <= conta_tx + 8'd1;
                        srclk_en  <= 1'b1;
                    end else begin
                        SER       <= 1'b0;
                        srclk_en  <= 1'b0;
                    end
                    LAT <= 1'b0;
                    OE  <= 1'b0;
                end
                3'd2: begin // Latch
                    LAT      <= 1'b1;
                    conta_oe <= 9'd0;
                    SER      <= 1'b0;
                    srclk_en <= 1'b0;
                end
                3'd3: begin // Activación de salida
                    LAT      <= 1'b0;
                    OE       <= 1'b1;
                    conta_oe <= conta_oe + 9'd1;
                    SER      <= 1'b0;
                    srclk_en <= 1'b0;
                end
                3'd4: begin // Cargar nueva fila
                    OE       <= 1'b0;
                    conta_tx <= 8'd0;
                    if (valid_frame) begin
                        reg_ser <= row_data;   // <<< sin part-select variable
                    end else begin
                        reg_ser <= 128'd0;
                    end
                    fila_cnt <= fila_cnt + 2'd1;
                    A        <= fila_cnt[0];
                    B        <= fila_cnt[1];
                    LAT      <= 1'b0;
                    SER      <= 1'b0;
                    srclk_en <= 1'b0;
                end
            endcase
        end
    end

endmodule

module uart_rx (
    input  clk,                  // Reloj del sistema
    input  rst,                  // Reset activo en bajo
    input  rx_pin,              // Entrada UART
    input  rx_data_ready,       // Señal externa: indica que ya se leyó el dato
    output reg [7:0] rx_data,   // Byte recibido
    output reg rx_data_valid     // Señal de validez del dato
);

    // Cálculo de ciclos de reloj por bit
    parameter CLK_FRE   = 27;       // Frecuencia de reloj en MHz
    parameter BAUD_RATE = 115200;    // Baud rate deseado
    localparam integer CYCLE = (CLK_FRE * 1000000) / BAUD_RATE;

    // Estados de la FSM
    localparam S_IDLE     = 3'd0;
    localparam S_START    = 3'd1;
    localparam S_REC_BYTE = 3'd2;
    localparam S_STOP     = 3'd3;
    localparam S_DATA     = 3'd4;

    reg [2:0] state, next_state;

    // Sincronización de entrada UART
    reg rx_d0, rx_d1;
    wire rx_negedge = rx_d1 & ~rx_d0;

    // Temporización y contadores
    reg [15:0] cycle_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  rx_bits;

    // Estabiliza la señal de entrada UART
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rx_d0 <= 1'b1;
            rx_d1 <= 1'b1;
        end else begin
            rx_d0 <= rx_pin;
            rx_d1 <= rx_d0;
        end
    end

    // Estado actual
    always @(posedge clk or negedge rst) begin
        if (!rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // Lógica de transición de estados
    always @(*) begin
        case (state)
            S_IDLE:     next_state = rx_negedge ? S_START : S_IDLE;
            S_START:    next_state = (cycle_cnt == CYCLE-1) ? S_REC_BYTE : S_START;
            S_REC_BYTE: next_state = (cycle_cnt == CYCLE-1 && bit_cnt == 3'd7) ? S_STOP : S_REC_BYTE;
            S_STOP:     next_state = (cycle_cnt == (CYCLE/2)-1) ? S_DATA : S_STOP;
            S_DATA:     next_state = S_IDLE;
            default:    next_state = S_IDLE;
        endcase
    end

    // Temporizador y contador de bits
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cycle_cnt <= 16'd0;
            bit_cnt   <= 3'd0;
        end else begin
            if (state == S_START || state == S_REC_BYTE || state == S_STOP)
                cycle_cnt <= (cycle_cnt == CYCLE-1) ? 16'd0 : cycle_cnt + 16'd1;
            else
                cycle_cnt <= 16'd0;

            if (state == S_REC_BYTE && cycle_cnt == CYCLE-1)
                bit_cnt <= bit_cnt + 3'd1;
            else if (state != S_REC_BYTE)
                bit_cnt <= 3'd0;
        end
    end

    // Captura de bits UART
    always @(posedge clk or negedge rst) begin
        if (!rst)
            rx_bits <= 8'd0;
        else if (state == S_REC_BYTE && cycle_cnt == ((CYCLE / 2) - 1))
            rx_bits[bit_cnt] <= rx_pin;
    end

    // Generación del dato de salida
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            rx_data       <= 8'd0;
            rx_data_valid <= 1'b0;
        end else begin
            if (state == S_STOP && next_state == S_DATA) begin
                rx_data       <= rx_bits;
                rx_data_valid <= 1'b1;
            end else if (rx_data_valid && rx_data_ready) begin
                rx_data_valid <= 1'b0;
            end
        end
    end

endmodule