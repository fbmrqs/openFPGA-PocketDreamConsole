module pdc_framebuffer (
    input logic reset, system_clk, memory_clk, video_clk,
    input logic pixel_valid,
    input logic [8:0] pixel_x,
    input logic [7:0] pixel_y,
    input logic [14:0] pixel_data,
    output logic pixel_ready,
    output logic [1:0] memory_read, memory_write,
    (* preserve *) output logic [43:0] memory_address,
    (* preserve *) output logic [31:0] memory_data,
    input logic [1:0] memory_busy, memory_valid,
    input logic [31:0] memory_q,
    output logic [23:0] video_rgb,
    output logic video_de, video_hs, video_vs,
    output logic underflow, write_fault,
    output logic [15:0] dropped_frames
);
    logic reset_memory;
    pdc_reset_sync reset_memory_sync (.clk(memory_clk),.async_reset(reset),.reset(reset_memory));
    logic reset_video;
    pdc_reset_sync reset_video_sync (.clk(video_clk),.async_reset(reset),.reset(reset_video));

    logic [32:0] pixel_packet;
    logic pixel_full, pixel_empty, pixel_pop, pixel_available;
    logic [10:0] pixel_level;
    logic [16:0] pixel_address;
    assign pixel_address=17'(int'(pixel_y)*320+int'(pixel_x));
    assign pixel_ready=!pixel_full && pixel_level<1022;
    pdc_async_fifo #(.WIDTH(33),.ADDRESS_BITS(10)) pixels (
        .reset,.write_clk(system_clk),.write_en(pixel_valid),
        .write_data({pixel_y==239 && pixel_x==319,pixel_address,pixel_data}),.full(pixel_full),
        .read_clk(memory_clk),.read_en(pixel_pop),.read_data(pixel_packet),.read_valid(pixel_available),.empty(pixel_empty),
        .write_level(pixel_level),.read_level());

    logic [8:0] x_count, y_count;
    logic frame_toggle, active_delay, hs_delay, vs_delay;
    logic scan_empty, scan_full, scan_valid, scan_push, visible, scan_reset;
    logic [14:0] scan_data, scan_input;
    logic [14:0] scan_level;
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) logic [1:0] display_sync, frame_sync;
    logic display_valid;
    assign visible=x_count>=10 && x_count<330 && y_count>=64 && y_count<304;
    pdc_async_fifo #(.WIDTH(15),.ADDRESS_BITS(14)) scanout (
        .reset(scan_reset),.write_clk(memory_clk),.write_en(scan_push),.write_data(scan_input),.full(scan_full),
        .read_clk(video_clk),.read_en(visible && display_sync[1]),.read_data(scan_data),.read_valid(scan_valid),.empty(scan_empty),
        .write_level(scan_level),.read_level());
    always_ff @(posedge video_clk or posedge reset_video) begin
        if (reset_video) begin
            x_count<=0;y_count<=0;frame_toggle<=0;active_delay<=0;hs_delay<=0;vs_delay<=0;
            video_rgb<=0;video_de<=0;video_hs<=0;video_vs<=0;underflow<=0;display_sync<=0;
        end else begin
            display_sync<={display_sync[0],display_valid};
            if (x_count==399) begin x_count<=0;y_count<=y_count+9'd1;end
            else x_count<=x_count+9'd1;
            if (x_count==0 && y_count==0) frame_toggle<=!frame_toggle;
            hs_delay<=x_count==3;vs_delay<=x_count==0 && y_count==0;
            active_delay<=visible && display_sync[1];
            video_de<=active_delay;video_hs<=hs_delay;video_vs<=vs_delay;video_rgb<=0;
            if (active_delay && scan_valid) video_rgb<={scan_data[14:10],scan_data[14:12],scan_data[9:5],scan_data[9:7],scan_data[4:0],scan_data[4:2]};
            if (visible && display_sync[1] && scan_empty) underflow<=1;
        end
    end

    // Three ordered frames absorb a late handoff without dropping a picture.
    // Alternate pixels use alternate PSRAM dies, sharing read/write bandwidth.
    logic seen_frame;
    logic [1:0] front_buffer, write_buffer, queued_frames;
    logic [16:0] expected_address, read_address, read_word_address, write_word_address;
    logic [32:0] held_pixel;
    logic [2:0] clear_scan;
    logic frame_boundary, swap_frame, finish_frame;
    logic [1:0] reading, read_received, read_launch;
    logic [29:0] read_pair;
    logic [1:0] write_pulse, read_pulse;
    wire write_chip=held_pixel[15];
    typedef enum logic [2:0] {IDLE, GET_PIXEL, WRITE_PIXEL, LAUNCH, COMMIT} writer_t;
    writer_t writer;
    function automatic logic [1:0] next_buffer(input logic [1:0] buffer_id);
        next_buffer=buffer_id==2 ? 2'd0 : buffer_id+2'd1;
    endfunction
    function automatic logic [16:0] buffer_base(input logic [1:0] buffer_id);
        case (buffer_id)
            0: buffer_base=17'd0;
            1: buffer_base=17'd38400;
            default: buffer_base=17'd76800;
        endcase
    endfunction
    assign pixel_pop=writer==IDLE && !pixel_empty;
    assign scan_reset=reset || clear_scan!=0;
    assign memory_write=write_pulse;
    assign memory_read=read_pulse;
    assign dropped_frames=16'b0;
    assign frame_boundary=frame_sync[1]!=seen_frame;
    assign swap_frame=frame_boundary && queued_frames!=0;
    assign finish_frame=writer==COMMIT && !memory_busy[write_chip] && held_pixel[32];
    genvar chip;
    generate for (chip=0;chip<2;chip=chip+1) begin : read_requests
        assign read_launch[chip]=!frame_boundary && clear_scan==0 && display_valid &&
            !reading[chip] && !read_received[chip] && !memory_busy[chip] &&
            !write_pulse[chip] && !read_pulse[chip] && !scan_full && scan_level<16380 && read_address<76800;
    end endgenerate
    always_ff @(posedge memory_clk or posedge reset_memory) begin
        if (reset_memory) begin
            frame_sync<=0;seen_frame<=0;front_buffer<=2;write_buffer<=0;queued_frames<=0;read_received<=0;read_pair<=0;
            display_valid<=0;expected_address<=0;read_address<=0;held_pixel<=0;
            read_word_address<=76800;write_word_address<=0;
            clear_scan<=4;reading<=0;scan_push<=0;scan_input<=0;write_pulse<=0;read_pulse<=0;
            memory_address<=0;memory_data<=0;writer<=IDLE;write_fault<=0;
        end else begin
            frame_sync<={frame_sync[0],frame_toggle};
            write_pulse<=0;read_pulse<=0;scan_push<=0;
            case ({finish_frame,swap_frame})
                2'b10: queued_frames<=queued_frames+2'd1;
                2'b01: queued_frames<=queued_frames-2'd1;
                default: ;
            endcase
            if (clear_scan!=0) clear_scan<=clear_scan-3'd1;
            if (frame_boundary) begin
                seen_frame<=frame_sync[1];clear_scan<=4;read_address<=0;reading<=0;read_received<=0;
                read_word_address<=buffer_base(swap_frame ? next_buffer(front_buffer) : front_buffer);
                if (swap_frame) begin front_buffer<=next_buffer(front_buffer);display_valid<=1;end
            end else if (clear_scan==0 && display_valid) begin
                for (int chip=0;chip<2;chip++) begin
                    if (reading[chip] && memory_valid[chip]) begin
                        read_pair[chip*15 +:15]<=memory_q[chip*16 +:15];
                        read_received[chip]<=1;reading[chip]<=0;
                    end else if (read_launch[chip]) begin
                        memory_address[chip*22 +:22]<={5'b0,read_word_address};
                        read_pulse[chip]<=1;reading[chip]<=1;
                    end
                end
                if (read_received==2'b11 && !scan_full && scan_level<16382) begin
                    scan_input<=read_pair[read_address[0]*15 +:15];scan_push<=1;
                    read_address<=read_address+17'd1;
                    if (read_address[0]) begin
                        read_received<=0;read_word_address<=read_word_address+17'd1;
                    end
                end
            end
            case (writer)
                IDLE: if (pixel_pop) writer<=GET_PIXEL;
                GET_PIXEL: if (pixel_available) begin
                    if (pixel_packet[31:15]!=expected_address) write_fault<=1;
                    expected_address<=pixel_packet[32] ? 17'b0 : expected_address+17'd1;
                    held_pixel<=pixel_packet;writer<=WRITE_PIXEL;
                end
                WRITE_PIXEL: if (queued_frames<2 && !memory_busy[write_chip] &&
                    !read_pulse[write_chip] && !write_pulse[write_chip] &&
                    !read_launch[write_chip]) begin
                    if (write_chip) begin
                        memory_address[43:22]<={5'b0,write_word_address};
                        memory_data[31:16]<={1'b0,held_pixel[14:0]};
                    end else begin
                        memory_address[21:0]<={5'b0,write_word_address};
                        memory_data[15:0]<={1'b0,held_pixel[14:0]};
                    end
                    write_pulse[write_chip]<=1;writer<=LAUNCH;
                end
                LAUNCH: if (memory_busy[write_chip]) writer<=COMMIT;
                COMMIT: if (!memory_busy[write_chip]) begin
                    if (held_pixel[32]) begin
                        write_buffer<=next_buffer(write_buffer);
                        write_word_address<=buffer_base(next_buffer(write_buffer));
                    end else if (write_chip) write_word_address<=write_word_address+17'd1;
                    writer<=IDLE;
                end
                default: writer<=IDLE;
            endcase
        end
    end
endmodule
