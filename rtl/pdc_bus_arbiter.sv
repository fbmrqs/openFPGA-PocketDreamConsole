module pdc_bus_arbiter #(
    parameter integer CLIENTS = 4,
    parameter integer ADDRESS_WIDTH = 22,
    parameter logic REGISTER_RESPONSE = 1
) (
    input logic clk, reset,
    input logic [CLIENTS-1:0] request, write,
    input logic [CLIENTS*ADDRESS_WIDTH-1:0] address,
    input logic [CLIENTS*16-1:0] write_data,
    output logic [CLIENTS-1:0] ack,
    output logic [15:0] read_data,
    output logic memory_request, memory_write,
    (* preserve, dont_retime, maxfan = 8 *) output logic [ADDRESS_WIDTH-1:0] memory_address,
    output wire [ADDRESS_WIDTH-1:0] memory_lookahead_address,
    output logic [15:0] memory_write_data,
    input logic memory_ack,
    input logic [15:0] memory_read_data
);
    localparam integer INDEX_WIDTH = $clog2(CLIENTS);
    logic [INDEX_WIDTH-1:0] owner, next_owner, selected;
    logic busy, turnaround;
    (* preserve, dont_retime, maxfan=8 *) logic [CLIENTS-1:0] held_grant;
    logic [15:0] response_data;
    logic [CLIENTS-1:0] response_ack;
    wire [CLIENTS-1:0] grant;
    wire [CLIENTS-1:0] priority_match [0:CLIENTS-1];
    logic selected_write;
    logic [ADDRESS_WIDTH-1:0] selected_address;
    logic [15:0] selected_data;
    function automatic logic [CLIENTS-1:0] preceding(input integer start, client);
        preceding='0;
        for (int offset=0;offset<CLIENTS;offset++)
            if (offset<(client-start+CLIENTS)%CLIENTS) preceding[(start+offset)%CLIENTS]=1'b1;
    endfunction
    wire [CLIENTS-1:0] active_grant=busy || turnaround ? held_grant : grant;
    genvar client, start;
    assign memory_lookahead_address=selected_address;
`ifdef PDC_VERIFY_MMIO_CYCLES
    always_ff @(posedge clk)
        if (!reset && busy)
            for (int input_client=0;input_client<CLIENTS;input_client++)
                if (held_grant[input_client] && (selected_address!=address[input_client*ADDRESS_WIDTH +: ADDRESS_WIDTH] ||
                    memory_lookahead_address!=selected_address))
                    $fatal(1,"Local bus address differs from the held owner payload");
`endif
    generate
        for (client=0;client<CLIENTS;client++) begin : grants
            for (start=0;start<CLIENTS;start++) begin : priorities
                localparam logic [CLIENTS-1:0] PRECEDING=preceding(start,client);
                assign priority_match[client][start]=next_owner==INDEX_WIDTH'(start) &&
                    request[client] && !(|(request & PRECEDING));
            end
            assign grant[client]=|priority_match[client];
        end
    endgenerate
    always_comb begin
        selected='0;selected_write=0;selected_data='0;selected_address='0;
        for (int client=0;client<CLIENTS;client++) begin
            selected|=INDEX_WIDTH'(client) & {INDEX_WIDTH{grant[client]}};
            selected_address|=address[client*ADDRESS_WIDTH +: ADDRESS_WIDTH] & {ADDRESS_WIDTH{active_grant[client]}};
            selected_write|=write[client] && active_grant[client];
            selected_data|=write_data[client*16 +: 16] & {16{active_grant[client]}};
        end
    end
    assign memory_request = busy;
    assign read_data = REGISTER_RESPONSE ? response_data : memory_read_data;
    assign ack = REGISTER_RESPONSE ? response_ack : held_grant & {CLIENTS{!reset && busy && memory_ack}};
    always_ff @(posedge clk) begin
        response_ack<='0;
        if (reset) begin
            owner <= 0; next_owner <= 0; busy <= 0; turnaround <= 0;held_grant<='0;response_data<=0;
            memory_write<=0;memory_address<=0;memory_write_data<=0;
        end else begin
            memory_write<=selected_write;memory_address<=selected_address;memory_write_data<=selected_data;
            if (busy) begin
            if (memory_ack) begin
                response_ack[owner]<=1;response_data<=memory_read_data;
                busy <= 0; turnaround <= 1;
                next_owner <= owner == INDEX_WIDTH'(CLIENTS-1) ? '0 : owner + 1'b1;
            end
        end else if (turnaround) begin
            if (!request[owner]) turnaround<=0;
        end else if (|grant) begin
            owner<=selected;held_grant<=grant;busy<=1;
        end
        end
    end
endmodule
