// Scanline renderer matching the vendored SPG200 reference (ISC).
module pdc_ppu (
    input logic clk, reset,
    output logic ready,
    input logic register_write,
    input logic [13:0] register_address,
    input logic [15:0] register_data,
    output logic [15:0] register_read_data,
    input logic start_line,
    input logic [7:0] line,
    output logic busy, line_done,
    output logic memory_request,
    (* preserve, dont_retime, maxfan=8 *) output logic [21:0] memory_address,
    input logic memory_ack,
    input logic [15:0] memory_data,
    input logic memory_line_valid,
    input logic [255:0] memory_line_data,
    output logic pixel_valid,
    input logic pixel_ready,
    output logic [8:0] pixel_x,
    output logic [7:0] pixel_y,
    output logic [14:0] pixel_data
);
    logic [15:0] bg [0:1][0:6];
    (* ramstyle = "M10K, no_rw_check" *) logic [15:0] palette [0:255];
    (* ramstyle = "M10K, no_rw_check" *) logic [8:0] line_scroll [0:255];
    (* ramstyle = "M10K, no_rw_check" *) logic [15:0] line_compress [0:255];
    (* ramstyle = "M10K, no_rw_check" *) logic [15:0] pixels [0:319];
    logic [15:0] sprite_segment;
    logic [8:0] compress_amount;
    logic [12:0] compress_offset;
    logic [7:0] fade;
    logic [1:0] blend_level;
    logic sprite_enabled;
    logic [5:0] stn_control;
    logic [9:0] clear_index;
    typedef enum logic [31:0] {
        IDLE = 32'd1 << 0,
        CLEAR_LINE = 32'd1 << 1,
        BG_START = 32'd1 << 2,
        BG_COMPRESS = 32'd1 << 3,
        BG_VALIDATE = 32'd1 << 4,
        BG_SCROLL_READ = 32'd1 << 5,
        BG_SCROLL = 32'd1 << 6,
        BG_TILE = 32'd1 << 7,
        BG_POSITION = 32'd1 << 8,
        BG_NUMBER_ADDRESS = 32'd1 << 9,
        TILE_NUMBER = 32'd1 << 10,
        TILE_ATTRIBUTE = 32'd1 << 11,
        BITMAP_LOW = 32'd1 << 12,
        BITMAP_HIGH = 32'd1 << 13,
        SPRITE_START = 32'd1 << 14,
        ROW_ADDRESS = 32'd1 << 15,
        WORD_ADDRESS = 32'd1 << 16,
        TILE_ADDRESS = 32'd1 << 17,
        TILE_SETUP = 32'd1 << 18,
        CLIP_SETUP = 32'd1 << 19,
        CLIP_DIVIDE = 32'd1 << 20,
        CLIP_APPLY = 32'd1 << 21,
        TILE_FETCH = 32'd1 << 22,
        TILE_WORD = 32'd1 << 23,
        TILE_PIXEL = 32'd1 << 24,
        TILE_NEXT = 32'd1 << 25,
        NEXT_BG_TILE = 32'd1 << 26,
        NEXT_OBJECT = 32'd1 << 27,
        EMIT = 32'd1 << 28,
        FINISH = 32'd1 << 29,
        SPRITE_RESTART = 32'd1 << 30,
        BG_SCROLL_POSITION = 32'd1 << 31
    } state_t;
    (* preserve, dont_retime *) state_t state;
    (* dont_retime *) state_t resume_state;
    logic [1:0] layer;
    logic bg_index, object_sprite;
    logic [3:0] sprite_passes;
    logic [31:0] sprite_groups [0:3];
    wire [7:0] scanned_sprite = output_x[7:0]-8'd2;
    wire [8:0] next_sprite_group = {sprite_index[8:3],3'b000}+9'd8;
    wire empty_sprite_group = !sprite_groups[layer][sprite_index[7:3]];
    logic [8:0] sprite_index, output_x;
    logic [7:0] screen_y;
    logic signed [11:0] screen_x, tile_x;
    logic [9:0] tile_width, tile_height;
    logic [3:0] width_shift, height_shift;
    (* preserve, dont_retime *) logic [8:0] scroll_x;
    logic [8:0] map_y;
    logic [11:0] tile_position;
    logic [7:0] map_tile_row;
    logic [8:0] map_tile_column;
    logic [15:0] tile_number, tile_attr;
    logic [3:0] tile_palette;
    logic hflip, vflip, blending;
    (* preserve *) logic [4:0] bpp;
    (* preserve, dont_retime *) logic [21:0] tile_address;
    logic [5:0] tile_row_y;
    logic [21:0] row_index, word_offset;
    logic [12:0] clip_address_low;
    logic [10:0] clip_address_high_zero, clip_address_high_one;
    logic [21:0] clip_address_delta;
    (* preserve *) logic [11:0] tile_end_offset;
    wire [21:0] row_words = row_index << (width_shift[1:0]-2'd3);
    (* preserve *) logic [31:0] pixel_buffer;
    (* preserve *) logic signed [6:0] bit_shift;
    logic [9:0] tile_pixel;
    logic [15:0] bitmap_low, fetched_word;
    logic rom_buffer_valid;
    logic [17:0] rom_buffer_address;
    logic [255:0] rom_buffer;
    wire buffered_word = rom_buffer_valid && tile_address[21:4]==rom_buffer_address;
    wire [15:0] rom_word = rom_buffer[tile_address[3:0]*16 +:16];
    wire [15:0] buffered_pixels = bpp==16 ? rom_word : {rom_word[7:0],rom_word[15:8]};
    logic [21:0] bitmap_address, next_memory_address;
    logic [16:0] compressed_product;
    logic signed [15:0] compressed_base, virtual_y;
    integer k, row_y, tile_y, tile_map_x;
    (* preserve *) logic [11:0] clip_distance;
    logic [11:0] skipped_words, skipped_pixels, clip_dividend, clip_quotient;
    logic [1:0] clip_remainder;
    logic [3:0] clip_count;
    wire [2:0] clip_partial = {clip_remainder,clip_dividend[11]};
    wire [11:0] clip_next_quotient = {clip_quotient[10:0],clip_partial>=3};
    logic [3:0] clip_bit_offset;
    always_comb begin
        case (bpp)
            2: clip_bit_offset = {skipped_pixels[2:0],1'b0};
            4: clip_bit_offset = {skipped_pixels[1:0],2'b0};
            6: clip_bit_offset = {skipped_pixels[2:0],1'b0}+{skipped_pixels[1:0],2'b0};
            8: clip_bit_offset = {skipped_pixels[0],3'b0};
            default: clip_bit_offset = 0;
        endcase
    end
    logic [15:0] word_value;
    logic [8:0] scroll_memory_q;
    logic [15:0] compress_memory_q,palette_memory_q,pixel_memory_q;
    wire [15:0] sprite_memory_q0,sprite_memory_q1,sprite_memory_q2,sprite_memory_q3;
`ifdef PDC_POISON_COLLISIONS
    logic [7:0] sprite_read_address [0:3];
    always_ff @(posedge clk)
        for (int plane=0;plane<4;plane++) sprite_read_address[plane]<=next_sprite_address;
`endif
`ifdef PDC_POISON_COLLISIONS
    logic scroll_collision, compress_collision, palette_collision, pixel_collision;
    logic [3:0] sprite_collision;
    always_ff @(posedge clk) begin
        scroll_collision<=!reset && ((!ready && clear_index<256) || (ready && register_write && register_address>=14'h2900 && register_address<14'h2a00)) &&
            (ready ? register_address[7:0] : clear_index[7:0])==(busy ? map_y[7:0] : register_address[7:0]);
        compress_collision<=!reset && ((!ready && clear_index<256) || (ready && register_write && register_address>=14'h2a00 && register_address<14'h2b00)) &&
            (ready ? register_address[7:0] : clear_index[7:0])==register_address[7:0];
        palette_collision<=!reset && ((!ready && clear_index<256) || (ready && register_write && register_address>=14'h2b00 && register_address<14'h2c00)) &&
            (ready ? register_address[7:0] : clear_index[7:0])==next_palette_address;
        for(int plane=0;plane<4;plane++)sprite_collision[plane]<=!reset &&
            (!ready || (register_write && register_address>=14'h2c00 && register_address<14'h3000)) &&
            sprite_write_address[1:0]==2'(plane) && sprite_write_address[9:2]==sprite_read_address[plane];
        pixel_collision<=!reset && ready && ((state[$clog2(CLEAR_LINE)] && output_x==next_pixel_address) ||
            (!state[$clog2(CLEAR_LINE)] && pixel_write_pending && pixel_write_address==next_pixel_address));
    end
    wire [8:0] scroll_q=scroll_collision ? 9'h1ad : scroll_memory_q;
    wire [15:0] compress_q=compress_collision ? 16'hdead : compress_memory_q;
    wire [15:0] sprite_q0=sprite_collision[0] ? 16'hdead : sprite_memory_q0;
    wire [15:0] sprite_q1=sprite_collision[1] ? 16'hdead : sprite_memory_q1;
    wire [15:0] sprite_q2=sprite_collision[2] ? 16'hdead : sprite_memory_q2;
    wire [15:0] sprite_q3=sprite_collision[3] ? 16'hdead : sprite_memory_q3;
    wire [15:0] palette_q=palette_collision ? 16'hdead : palette_memory_q;
    wire [15:0] pixel_q=pixel_collision ? 16'hdead : pixel_memory_q;
`else
    wire [8:0] scroll_q = scroll_memory_q;
    wire [15:0] compress_q = compress_memory_q;
    wire [15:0] sprite_q0 = sprite_memory_q0;
    wire [15:0] sprite_q1 = sprite_memory_q1;
    wire [15:0] sprite_q2 = sprite_memory_q2;
    wire [15:0] sprite_q3 = sprite_memory_q3;
    wire [15:0] palette_q = palette_memory_q;
    wire [15:0] pixel_q = pixel_memory_q;
`endif
    logic [7:0] next_sprite_address, next_palette_address;
    logic [8:0] next_pixel_address;
    logic [15:0] color_code, new_pixel, blended_pixel, sprite_write_data;
    logic pixel_write_pending, pixel_blend_pending;
    logic pixel_sample_valid, pixel_sample_direct, pixel_sample_blend;
    logic [8:0] pixel_sample_address;
    logic [15:0] pixel_sample_code, pixel_sample_previous;
    logic [1:0] pixel_sample_level;
    logic [8:0] pixel_write_address;
    logic [15:0] pixel_write_color, pixel_previous_color;
    logic [1:0] pixel_blend_level;
    logic [9:0] sprite_write_address;
    logic consume_pixel, skip_sprite;
    logic [5:0] sprite_half_height;
    logic signed [9:0] sprite_distance, sprite_row;
    logic sprite_inside;
    wire [7:0] sprite_x_bias={3'b100,~&sprite_q3[5:4],~sprite_q3[5],~|sprite_q3[5:4],2'b00};
    wire signed [11:0] advanced_screen_x=screen_x+$signed({2'b0,tile_width});

    function automatic logic [21:0] increment22(input logic [21:0] value);
        return {11'(value[21:11]+11'(&value[10:0])),11'(value[10:0]+11'd1)};
    endfunction
    function automatic logic [21:0] decrement22(input logic [21:0] value);
        return {11'(value[21:11]-11'(~|value[10:0])),11'(value[10:0]-11'd1)};
    endfunction
    function automatic [11:0] tile_words(input logic [11:0] count, input logic [4:0] depth);
        logic [13:0] triple;
        triple={2'b0,count}+({2'b0,count}<<1);
        case (depth)
            2: return count>>3;
            4: return count>>2;
            6: return 12'(triple>>3);
            8: return count>>1;
            default: return count;
        endcase
    endfunction
    function automatic [15:0] unpack_color(input logic [31:0] buffer_value,
        input logic signed [6:0] shift_value, input logic [4:0] depth, input logic flip);
        logic signed [6:0] position;
        logic [31:0] shifted;
        begin
            position = flip ? 7'd32-7'(depth)-shift_value : shift_value;
            shifted = position >= 0 && position < 32 ? buffer_value >> position[4:0] : 32'b0;
            case (depth)
                2: unpack_color = {14'b0,shifted[1:0]};
                4: unpack_color = {12'b0,shifted[3:0]};
                6: unpack_color = {10'b0,shifted[5:0]};
                8: unpack_color = {8'b0,shifted[7:0]};
                16: unpack_color = shifted[15:0];
                default: unpack_color = 0;
            endcase
        end
    endfunction
    function automatic [7:0] palette_index(input logic [15:0] code,
        input logic [4:0] depth, input logic [3:0] pal);
        case (depth)
            2,4: palette_index = {pal,code[3:0]};
            6: palette_index = {pal[3:2],code[5:0]};
            default: palette_index = code[7:0];
        endcase
    endfunction
    function automatic [4:0] blend_component(input logic [4:0] previous_color,
        input logic [4:0] next_color, input logic [1:0] alpha);
        logic [6:0] previous_product, next_product;
        begin
            case (alpha)
                0: begin previous_product=(7'(previous_color)<<1)+7'(previous_color);next_product=7'(next_color);end
                1: begin previous_product=7'(previous_color)<<1;next_product=7'(next_color)<<1;end
                2: begin previous_product=7'(previous_color);next_product=(7'(next_color)<<1)+7'(next_color);end
                3: begin previous_product=0;next_product=7'(next_color)<<2;end
            endcase
            blend_component = previous_product[6:2]+next_product[6:2];
        end
    endfunction
    always_comb begin
        consume_pixel = state[$clog2(TILE_PIXEL)] && tile_pixel < tile_width && tile_x < 320 && bit_shift >= 0;
        sprite_half_height = 4 << sprite_q3[7:6];
        sprite_distance = 10'($signed({~screen_y[7],screen_y[6:0]}))+10'($signed(sprite_q2[8:0]));
        sprite_row = sprite_distance+10'(sprite_half_height);
        case (sprite_q3[7:6])
            0: sprite_inside = sprite_distance[9:2]==0 || &sprite_distance[9:2];
            1: sprite_inside = sprite_distance[9:3]==0 || &sprite_distance[9:3];
            2: sprite_inside = sprite_distance[9:4]==0 || &sprite_distance[9:4];
            3: sprite_inside = sprite_distance[9:5]==0 || &sprite_distance[9:5];
        endcase
        skip_sprite = sprite_q0 == 0 || sprite_q3[13:12] != layer ||
            !sprite_inside;
        next_sprite_address=register_address[9:2];
        if (busy) begin
            next_sprite_address=object_sprite ? sprite_index[7:0]+8'd1 : 8'd0;
            if (state[$clog2(CLEAR_LINE)]) next_sprite_address=output_x[7:0];
            if (state[$clog2(NEXT_OBJECT)] && bg_index) next_sprite_address=1;
            if (state[$clog2(TILE_NEXT)] && object_sprite) next_sprite_address=sprite_index[7:0]+8'd2;
            if (state[$clog2(SPRITE_START)])
                next_sprite_address=!sprite_enabled || sprite_index==256 || !sprite_passes[layer] ? 8'd0 :
                    empty_sprite_group ? next_sprite_group[7:0] : sprite_index[7:0]+8'd2;
            if (state[$clog2(SPRITE_RESTART)]) next_sprite_address=sprite_index[7:0]+8'd1;
        end
        color_code = unpack_color(pixel_buffer,bit_shift,bpp,hflip);
        next_palette_address = busy ? palette_index(color_code,bpp,tile_palette) : register_address[7:0];
        next_pixel_address = 9'(tile_x);
        if (state[$clog2(EMIT)]) next_pixel_address = pixel_ready ? output_x+9'd1 : output_x;
        else if (state[$clog2(SPRITE_START)] || state[$clog2(NEXT_OBJECT)]) next_pixel_address = 0;
        else if (consume_pixel) next_pixel_address = 9'(tile_x+12'd1);
        new_pixel = pixel_sample_direct ? pixel_sample_code : palette_q;
        blended_pixel = pixel_write_color;
        if (pixel_blend_pending) blended_pixel = {1'b0,
            blend_component(pixel_previous_color[14:10],pixel_write_color[14:10],pixel_blend_level),
            blend_component(pixel_previous_color[9:5],pixel_write_color[9:5],pixel_blend_level),
            blend_component(pixel_previous_color[4:0],pixel_write_color[4:0],pixel_blend_level)};
        sprite_write_address = ready ? register_address[9:0] : clear_index;
        sprite_write_data = ready ? register_data : 16'b0;
        case (sprite_write_address[1:0])
            1,2: sprite_write_data = sprite_write_data & 16'h1ff;
            3: sprite_write_data = sprite_write_data & 16'h7fff;
            default: ;
        endcase
    end

    always_comb begin
        register_read_data = 0;
        case (register_address)
            14'h2810: register_read_data = bg[0][0];
            14'h2811: register_read_data = bg[0][1];
            14'h2812: register_read_data = bg[0][2];
            14'h2813: register_read_data = bg[0][3];
            14'h2814: register_read_data = bg[0][4];
            14'h2815: register_read_data = bg[0][5];
            14'h2816: register_read_data = bg[1][0];
            14'h2817: register_read_data = bg[1][1];
            14'h2818: register_read_data = bg[1][2];
            14'h2819: register_read_data = bg[1][3];
            14'h281a: register_read_data = bg[1][4];
            14'h281b: register_read_data = bg[1][5];
            14'h281c: register_read_data = {7'b0,compress_amount};
            14'h281d: register_read_data = {3'b0,compress_offset};
            14'h2820: register_read_data = bg[0][6];
            14'h2821: register_read_data = bg[1][6];
            14'h2822: register_read_data = sprite_segment;
            14'h282a: register_read_data = {14'b0,blend_level};
            14'h2830: register_read_data = {8'b0,fade};
            14'h2842: register_read_data = {15'b0,sprite_enabled};
            14'h2854: register_read_data = {10'b0,stn_control};
            default: begin
                if (register_address >= 14'h2900 && register_address < 14'h2a00)
                    register_read_data = {7'b0,scroll_q};
                if (register_address >= 14'h2a00 && register_address < 14'h2b00)
                    register_read_data = compress_q;
                if (register_address >= 14'h2b00 && register_address < 14'h2c00)
                    register_read_data = palette_q;
                if (register_address >= 14'h2c00 && register_address < 14'h3000)
                    case (register_address[1:0])
                        0: register_read_data = sprite_q0;
                        1: register_read_data = sprite_q1;
                        2: register_read_data = sprite_q2;
                        3: register_read_data = sprite_q3;
                    endcase
            end
        endcase
    end
    wire sprite_write = !reset && (!ready || (register_write && register_address>=14'h2c00 && register_address<14'h3000));
    pdc_sprite_bank sprites_0(.clk, .write(sprite_write && sprite_write_address[1:0]==2'd0),
        .write_address(sprite_write_address[9:2]), .write_data(sprite_write_data),
        .read_address(next_sprite_address), .read_data(sprite_memory_q0));
    pdc_sprite_bank sprites_1(.clk, .write(sprite_write && sprite_write_address[1:0]==2'd1),
        .write_address(sprite_write_address[9:2]), .write_data(sprite_write_data),
        .read_address(next_sprite_address), .read_data(sprite_memory_q1));
    pdc_sprite_bank sprites_2(.clk, .write(sprite_write && sprite_write_address[1:0]==2'd2),
        .write_address(sprite_write_address[9:2]), .write_data(sprite_write_data),
        .read_address(next_sprite_address), .read_data(sprite_memory_q2));
    pdc_sprite_bank sprites_3(.clk, .write(sprite_write && sprite_write_address[1:0]==2'd3),
        .write_address(sprite_write_address[9:2]), .write_data(sprite_write_data),
        .read_address(next_sprite_address), .read_data(sprite_memory_q3));
    task automatic fetch(input logic [21:0] address, input state_t next_state);
        next_memory_address = address; memory_request <= 1; resume_state <= next_state; state <= TILE_FETCH;
    endtask
    always_ff @(posedge clk) begin
        if (reset) bpp<=0;
        else if (state[$clog2(TILE_ATTRIBUTE)]) bpp<={1'b0,({1'b0,bg[bg_index][2][1:0]}+3'd1),1'b0};
        else if (state[$clog2(BITMAP_HIGH)]) bpp<=bg[bg_index][3][7] ? 5'd16 :
            {1'b0,({1'b0,bg[bg_index][2][1:0]}+3'd1),1'b0};
        else if (state[$clog2(SPRITE_START)]) bpp<={1'b0,({1'b0,sprite_q3[1:0]}+3'd1),1'b0};
    end
    always @(posedge clk) begin
        clip_distance<=12'(0-screen_x);
        skipped_words<=tile_words(clip_distance,bpp);
        scroll_memory_q<=line_scroll[busy ? map_y[7:0] : register_address[7:0]];
        compress_memory_q<=line_compress[register_address[7:0]];
        palette_memory_q<=palette[next_palette_address];pixel_memory_q<=pixels[next_pixel_address];
        pixel_sample_valid<=!reset && ready && consume_pixel && tile_x>=0;
        pixel_sample_address<=9'(tile_x);pixel_sample_code<=color_code;pixel_sample_direct<=bpp==16;
        pixel_sample_previous<=pixel_q;pixel_sample_blend<=blending && !pixel_q[15];pixel_sample_level<=blend_level;
        pixel_write_pending<=!reset && ready && pixel_sample_valid && !new_pixel[15];
        pixel_write_address<=pixel_sample_address;pixel_write_color<=new_pixel;
        pixel_previous_color<=pixel_sample_previous;pixel_blend_pending<=pixel_sample_blend;pixel_blend_level<=pixel_sample_level;
        if (!reset) begin
            if ((!ready && clear_index < 256) || (ready && register_write && register_address >= 14'h2900 && register_address < 14'h2a00))
                line_scroll[ready ? register_address[7:0] : clear_index[7:0]] <= ready ? register_data[8:0] : 9'b0;
            if ((!ready && clear_index < 256) || (ready && register_write && register_address >= 14'h2a00 && register_address < 14'h2b00))
                line_compress[ready ? register_address[7:0] : clear_index[7:0]] <= ready ? register_data : 16'b0;
            if ((!ready && clear_index < 256) || (ready && register_write && register_address >= 14'h2b00 && register_address < 14'h2c00))
                palette[ready ? register_address[7:0] : clear_index[7:0]] <= ready ? register_data : 16'b0;
            if (ready && state[$clog2(CLEAR_LINE)]) pixels[output_x] <= 16'h8000;
            else if (ready && pixel_write_pending) pixels[pixel_write_address] <= blended_pixel;
        end
        pixel_valid <= 0; line_done <= 0;
        if (reset) begin
            ready<= 0; clear_index = 0; busy<= 0; memory_request <= 0; memory_address <= 0;
            pixel_x <= 0; pixel_y <= 0; pixel_data <= 0; state <= IDLE; resume_state <= IDLE;
            sprite_segment <= 0; compress_amount <= 9'h20; compress_offset <= 0;
            fade <= 0; blend_level <= 0; sprite_enabled <= 0; stn_control <= 0;
            for (k = 0; k < 7; k = k + 1) begin bg[0][k] <= 0; bg[1][k] <= 0; end
            layer = 0; bg_index = 0; object_sprite <= 0;
            sprite_passes <= 0;rom_buffer_valid<=0;rom_buffer_address<=0;rom_buffer<='0;
            for (k=0;k<4;k=k+1) sprite_groups[k]<=0;
            sprite_index <= 0; output_x = 0; screen_y = 0; screen_x <= 0; tile_x = 0;
            tile_width = 0; tile_height = 0; width_shift = 0; height_shift = 0; scroll_x = 0; map_y <= 0; tile_position = 0;
            tile_number = 0; tile_attr = 0; tile_palette = 0; hflip <= 0; vflip = 0;
            blending = 0; tile_address <= 0; tile_end_offset <= 0; pixel_buffer <= 0; bit_shift = 0;
            tile_pixel = 0; bitmap_low = 0; fetched_word <= 0; bitmap_address = 0;
        end else if (!ready) begin
            if (clear_index == 1023) ready<= 1; else clear_index = clear_index + 10'd1;
        end else begin
            next_memory_address=tile_address;
            if (register_write) begin
                case (register_address)
                    14'h2810: bg[0][0] <= register_data & 16'h1ff;
                    14'h2811: bg[0][1] <= register_data & 16'hff;
                    14'h2812: bg[0][2] <= register_data & 16'h3fff;
                    14'h2813: bg[0][3] <= register_data & 16'h1ff;
                    14'h2814: bg[0][4] <= register_data & 16'h3fff;
                    14'h2815: bg[0][5] <= register_data & 16'h3fff;
                    14'h2816: bg[1][0] <= register_data & 16'h1ff;
                    14'h2817: bg[1][1] <= register_data & 16'hff;
                    14'h2818: bg[1][2] <= register_data & 16'h3fff;
                    14'h2819: bg[1][3] <= register_data & 16'h1ff;
                    14'h281a: bg[1][4] <= register_data & 16'h3fff;
                    14'h281b: bg[1][5] <= register_data & 16'h3fff;
                    14'h281c: compress_amount <= register_data[8:0];
                    14'h281d: compress_offset <= register_data[12:0];
                    14'h2820: bg[0][6] <= register_data;
                    14'h2821: bg[1][6] <= register_data;
                    14'h2822: sprite_segment <= register_data;
                    14'h282a: blend_level <= register_data[1:0];
                    14'h2830: fade <= register_data[7:0];
                    14'h2842: sprite_enabled <= register_data[0];
                    14'h2854: stn_control <= register_data[5:0];
                    default: begin

                    end
                endcase
            end
            unique case (1'b1)
                state[$clog2(IDLE)]: if (start_line) begin
                    sprite_passes <= 0;rom_buffer_valid<=0;
                    for (k=0;k<4;k=k+1) sprite_groups[k]<=0;
                    busy<= 1; screen_y = line; output_x = 0; state <= CLEAR_LINE;
                    layer = 0; bg_index = 0; object_sprite <= 0; sprite_index <= 0;
                end
                state[$clog2(CLEAR_LINE)]: begin
                    // Scan the two-clock sprite RAM while clearing the line.
                    if (output_x>=2 && output_x<258 && sprite_q0!=0 && sprite_inside) begin
                        sprite_passes[sprite_q3[13:12]] <= 1;
                        sprite_groups[sprite_q3[13:12]][scanned_sprite[7:3]] <= 1;
                    end
                    if (output_x == 319) state <= BG_START; else output_x = output_x + 9'd1;
                end
                state[$clog2(BG_START)]: begin
                    object_sprite <= 0;
                    if (!bg[bg_index][3][3] || bg[bg_index][2][13:12] != layer) state <= NEXT_OBJECT;
                    else begin
                        if (bg[bg_index][3][6]) begin
                            compressed_product<=17'(screen_y)*17'(compress_amount);
                            compressed_base<=16'($signed(compress_offset))+16'sd128;
                            state <= BG_COMPRESS;
                        end else begin virtual_y<=16'(screen_y);state <= BG_VALIDATE;end
                    end
                end
                state[$clog2(BG_COMPRESS)]: begin
                    virtual_y<=$signed({4'b0,compressed_product[16:5]})+compressed_base-$signed({5'b0,compress_amount,2'b0});
                    state <= BG_VALIDATE;
                end
                state[$clog2(BG_VALIDATE)]: if (virtual_y < 0 || virtual_y >= 240) state <= NEXT_OBJECT;
                    else begin
                        map_y<={1'b0,8'(virtual_y)+bg[bg_index][1][7:0]};
                        tile_width=10'(8 << bg[bg_index][2][5:4]);tile_height=10'(8 << bg[bg_index][2][7:6]);
                        width_shift=4'd3+{2'b0,bg[bg_index][2][5:4]};height_shift=4'd3+{2'b0,bg[bg_index][2][7:6]};
                        state <= BG_SCROLL_READ;
                    end
                state[$clog2(BG_SCROLL_READ)]: state <= BG_SCROLL;
                state[$clog2(BG_SCROLL)]: begin
                    scroll_x <= 9'(bg[bg_index][0] + (bg[bg_index][3][4] ? {7'b0,scroll_q} : 16'b0));
                    state <= BG_SCROLL_POSITION;
                end
                state[$clog2(BG_SCROLL_POSITION)]: begin
                    if (bg[bg_index][3][0]) begin
                        tile_width = 512; screen_x <= 12'(0-int'(scroll_x));
                        fetch({6'b0,bg[bg_index][4]} + 22'(map_y),BITMAP_LOW);
                    end else begin
                        screen_x <= 12'(0-(int'(scroll_x) & (int'(tile_width)-1))); state <= BG_TILE;
                    end
                end
                state[$clog2(BG_TILE)]: if (screen_x >= 320) state <= NEXT_OBJECT;
                    else begin
                        map_tile_row<=map_y[7:0]>>height_shift[2:0];
                        map_tile_column<=9'(9'(screen_x)+scroll_x)>>width_shift[2:0];
                        state <= BG_POSITION;
                    end
                state[$clog2(BG_POSITION)]: begin
                    tile_position<=bg[bg_index][3][2] ? 12'b0 :
                        (12'(map_tile_row)<<(4'd9-width_shift))+12'(map_tile_column);
                    state <= BG_NUMBER_ADDRESS;
                end
                state[$clog2(BG_NUMBER_ADDRESS)]: fetch({6'b0,bg[bg_index][4]}+22'(tile_position),TILE_NUMBER);
                state[$clog2(TILE_NUMBER)]: begin
                    tile_number = fetched_word;
                    if (tile_number == 0) state <= NEXT_BG_TILE;
                    else if (bg[bg_index][3][1]) begin
                        tile_palette = bg[bg_index][2][11:8]; vflip = bg[bg_index][2][3];
                        hflip <= bg[bg_index][2][2]; blending = bg[bg_index][3][8]; state <= TILE_ATTRIBUTE;
                    end else fetch({6'b0,bg[bg_index][5]} + 22'(tile_position >> 1),TILE_ATTRIBUTE);
                end
                state[$clog2(TILE_ATTRIBUTE)]: begin
                    if (!bg[bg_index][3][1]) begin
                        tile_attr = tile_position[0] ? fetched_word >> 8 : fetched_word;
                        tile_palette = tile_attr[3:0]; vflip = tile_attr[5]; hflip <= tile_attr[4]; blending = tile_attr[6];
                    end
                    row_y = int'(map_y) & (int'(tile_height)-1);
                    tile_y = vflip ? int'(tile_height)-row_y-1 : row_y;

                    tile_row_y = 6'(tile_y);
                    state <= ROW_ADDRESS;
                end
                state[$clog2(BITMAP_LOW)]: begin
                    bitmap_low = fetched_word;
                    fetch({6'b0,bg[bg_index][5]} + 22'(map_y >> 1),BITMAP_HIGH);
                end
                state[$clog2(BITMAP_HIGH)]: begin
                    tile_address <= {6'(map_y[0] ? fetched_word >> 8 : fetched_word),bitmap_low};
                    bitmap_address = {6'(map_y[0] ? fetched_word >> 8 : fetched_word),bitmap_low};

                    tile_palette = bg[bg_index][2][11:8]; hflip <= 0; blending = bg[bg_index][3][8]; state <= TILE_SETUP;
                end
                state[$clog2(SPRITE_START)]: begin
                    screen_x <= 12'($signed(sprite_q1[8:0]))+12'(sprite_x_bias);
                    object_sprite <= 1;
                    if (!sprite_enabled || sprite_index == 256 || !sprite_passes[layer]) begin
                        if (layer == 3) begin output_x = 0; state <= EMIT; end
                        else begin layer = layer + 2'd1; bg_index = 0; sprite_index <= 0; state <= BG_START; end
                    end else if (empty_sprite_group) begin
                        sprite_index <= next_sprite_group; state <= SPRITE_RESTART;
                    end else begin
                        tile_number = sprite_q0;
                        tile_attr = sprite_q3;
                        if (skip_sprite) sprite_index <= sprite_index + 9'd1;
                        else begin
                            tile_width = 10'(8 << tile_attr[5:4]); tile_height = 10'(8 << tile_attr[7:6]);
                            width_shift = 4'd3+{2'b0,tile_attr[5:4]}; height_shift = 4'd3+{2'b0,tile_attr[7:6]};

                            tile_palette = tile_attr[11:8]; hflip <= tile_attr[2]; blending = tile_attr[14];

                            tile_row_y = tile_attr[3] ? (6'(tile_height)-6'd1)^sprite_row[5:0] : sprite_row[5:0];
                            state <= ROW_ADDRESS;
                        end
                    end
                end
                state[$clog2(SPRITE_RESTART)]: state<=SPRITE_START;
                state[$clog2(ROW_ADDRESS)]: begin
                    row_index <= ({3'b0,tile_number,3'b0} << (height_shift[1:0]-2'd3)) + {16'b0,tile_row_y};
                    state <= WORD_ADDRESS;
                end
                state[$clog2(WORD_ADDRESS)]: begin
                    tile_end_offset <= hflip ? tile_words(12'(tile_width),bpp)-12'd1 : 12'd0;
                    case (bpp)
                        2: word_offset <= row_words;
                        4: word_offset <= row_words<<1;
                        6: word_offset <= row_words+(row_words<<1);
                        default: word_offset <= row_words<<2;
                    endcase
                    state <= TILE_ADDRESS;
                end
                state[$clog2(TILE_ADDRESS)]: begin
                    tile_address <= (22'(object_sprite ? sprite_segment : bg[bg_index][6])<<6)+word_offset;
                    state <= TILE_SETUP;
                end
                state[$clog2(TILE_SETUP)]: begin
                    pixel_buffer <= 0; bit_shift = 7'(0-int'(bpp)); tile_pixel = 0; tile_x = screen_x;
                    if (hflip) tile_address <= tile_address + 22'(tile_end_offset);
                    if (screen_x < 0) begin
                        state <= CLIP_SETUP;
                    end else state <= TILE_PIXEL;
                end
                state[$clog2(CLIP_SETUP)]: begin
                    clip_address_delta=hflip ? {10'h3ff,~skipped_words} : {10'b0,skipped_words};
                    clip_address_low<={1'b0,tile_address[10:0],1'b1}+{1'b0,clip_address_delta[10:0],hflip};
                    clip_address_high_zero<=tile_address[21:11]+clip_address_delta[21:11];
                    clip_address_high_one<=11'(({tile_address[21:11],1'b1}+{clip_address_delta[21:11],1'b1})>>1);
                    case (bpp)
                        2: skipped_pixels<=skipped_words<<3;
                        4: skipped_pixels<=skipped_words<<2;
                        8: skipped_pixels<=skipped_words<<1;
                        default: skipped_pixels<=skipped_words;
                    endcase
                    if (bpp==6) begin
                        clip_dividend=(skipped_words<<3)+12'd2;
                        clip_quotient=0;clip_remainder=0;clip_count=12;
                        state <= CLIP_DIVIDE;
                    end else state <= CLIP_APPLY;
                end
                state[$clog2(CLIP_DIVIDE)]: begin
                    clip_remainder=2'(clip_partial>=3 ? clip_partial-3'd3 : clip_partial);
                    clip_quotient=clip_next_quotient;clip_dividend=clip_dividend<<1;
                    clip_count=clip_count-4'd1;
                    if (clip_count==0) begin skipped_pixels<=clip_next_quotient;state <= CLIP_APPLY;end
                end
                state[$clog2(CLIP_APPLY)]: begin
                    tile_address <= {clip_address_low[12] ? clip_address_high_one : clip_address_high_zero,clip_address_low[11:1]};
                    tile_pixel = 10'(skipped_pixels); tile_x = screen_x + 12'(skipped_pixels);
                    bit_shift = bit_shift - 7'({3'b0,clip_bit_offset});
                    state <= TILE_PIXEL;
                end
                state[$clog2(TILE_FETCH)]: if (memory_ack) begin
                    if (memory_line_valid) begin
                        rom_buffer_valid<=1;rom_buffer_address<=memory_address[21:4];rom_buffer<=memory_line_data;
                    end
                    fetched_word <= memory_data; memory_request <= 0; state <= resume_state;
                    if (resume_state==TILE_WORD) begin
                        word_value = bpp == 16 ? memory_data : {memory_data[7:0],memory_data[15:8]};
                        pixel_buffer <= hflip ? {word_value,pixel_buffer[31:16]} : {pixel_buffer[15:0],word_value};
                        bit_shift = bit_shift + 7'd16; state <= TILE_PIXEL;
                    end
                end
                state[$clog2(TILE_PIXEL)]: if (tile_pixel >= tile_width || tile_x >= 320) state <= TILE_NEXT;
                    else if (bit_shift < 0) begin
                        if (buffered_word) begin
                            pixel_buffer <= hflip ? {buffered_pixels,pixel_buffer[31:16]} : {pixel_buffer[15:0],buffered_pixels};
                            bit_shift = bit_shift+7'd16;
                        end else fetch(tile_address,TILE_WORD);
                        tile_address <= hflip ? decrement22(tile_address) : increment22(tile_address);
                    end else begin
                        bit_shift = bit_shift-7'(bpp); tile_pixel = tile_pixel+10'd1; tile_x = tile_x+12'd1;
                        // The palette pipeline consumed the old buffer. Prepare its next word in parallel.
                        if (bit_shift<0 && tile_pixel<tile_width && tile_x<320 && buffered_word) begin
                            pixel_buffer <= hflip ? {buffered_pixels,pixel_buffer[31:16]} : {pixel_buffer[15:0],buffered_pixels};
                            bit_shift = bit_shift+7'd16;
                            tile_address <= hflip ? decrement22(tile_address) : increment22(tile_address);
                        end
                    end
                state[$clog2(TILE_NEXT)]: if (object_sprite) begin sprite_index <= sprite_index+9'd1; state <= SPRITE_START; end
                    else state <= NEXT_BG_TILE;
                state[$clog2(NEXT_BG_TILE)]: begin
                    screen_x <= advanced_screen_x;
                    if (!bg[bg_index][3][0]) state <= BG_TILE;
                    else if (advanced_screen_x >= 320) state <= NEXT_OBJECT;
                    else begin tile_address <= bitmap_address; state <= TILE_SETUP; end
                end
                state[$clog2(NEXT_OBJECT)]: if (!bg_index) begin bg_index = 1; state <= BG_START; end
                    else begin sprite_index <= 0; state <= SPRITE_START; end
                state[$clog2(EMIT)]: if (pixel_ready) begin
                    pixel_valid <= 1; pixel_x <= output_x; pixel_y <= screen_y;
                    pixel_data <= pixel_q[15] ? 15'b0 : pixel_q[14:0];
                    if (output_x == 319) state <= FINISH; else output_x = output_x+9'd1;
                end
                state[$clog2(FINISH)]: begin line_done <= 1; busy<= 0; state <= IDLE; end
                default: state <= IDLE;
            endcase
            if (!memory_request) memory_address<=next_memory_address;
        end
    end
`ifdef PDC_VERIFY_MMIO_CYCLES
    always @(posedge clk) if (!reset) begin
        if (!$onehot(state) || !$onehot(resume_state))
            $fatal(1,"Graphics controller state is not one-hot");
    end
`endif
endmodule

// Fixed sprite planes use two-clock reads and same-edge writes.
module pdc_sprite_bank(
    input logic clk, write,
    input logic [7:0] write_address, read_address,
    input logic [15:0] write_data,
    output logic [15:0] read_data
);
`ifdef ALTERA_RESERVED_QIS
    altsyncram #(
        .lpm_type("altsyncram"), .operation_mode("DUAL_PORT"),
        .intended_device_family("Cyclone V"), .ram_block_type("M10K"),
        .width_a(16), .width_b(16), .widthad_a(8), .widthad_b(8),
        .numwords_a(256), .numwords_b(256),
        .address_reg_b("CLOCK0"), .outdata_reg_b("CLOCK0"),
        .clock_enable_input_a("BYPASS"), .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE")
    ) memory (
        .clock0(clk), .clock1(1'b1), .clocken0(1'b1), .clocken1(1'b1),
        .clocken2(1'b1), .clocken3(1'b1), .aclr0(1'b0), .aclr1(1'b0),
        .addressstall_a(1'b0), .addressstall_b(1'b0), .wren_a(write),
        .address_a(write_address), .data_a(write_data), .wren_b(1'b0),
        .address_b(read_address), .data_b(16'b0), .q_a(), .q_b(read_data),
        .rden_a(1'b1), .rden_b(1'b1), .byteena_a(1'b1), .byteena_b(1'b1), .eccstatus()
    );
`else
    logic [15:0] words[0:255];
    logic [7:0] local_read_address;
    always_ff @(posedge clk) begin
        local_read_address<=read_address;
        read_data<=words[local_read_address];
        if (write) words[write_address]<=write_data;
    end
`endif
endmodule
