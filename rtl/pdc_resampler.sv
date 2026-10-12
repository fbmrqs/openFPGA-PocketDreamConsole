module pdc_resampler (
    input logic clk, reset, sample_valid,
    input logic signed [15:0] sample_left, sample_right,
    output logic output_valid,
    output logic signed [15:0] output_left, output_right
);
    logic [8:0] phase;
    logic [6:0] weight, remainder;
    logic signed [15:0] staged_left, staged_right;
    logic [6:0] staged_weight, staged_remainder;
    logic staged_valid, staged_boundary;
    logic boundary, input_valid, input_boundary, weighted_valid, weighted_boundary, sum_valid, magnitude_valid, operand_valid, partial_valid, combined_valid, halves_valid, product_valid;
    (* preserve, dont_merge *) logic signed [15:0] sample_operand [0:3];
    (* preserve, dont_merge *) logic [6:0] coefficient [0:3];
    (* preserve, dont_merge *) logic signed [22:0] weighted_left, weighted_right, remainder_left, remainder_right;
    logic signed [22:0] weighted_left_dsp,weighted_right_dsp,remainder_left_dsp,remainder_right_dsp;
    logic dsp_valid,dsp_boundary;
    (* dont_retime *) logic [27:0] upper_left_groups, upper_right_groups;
    logic upper_groups_valid, upper_groups_left_negative, upper_groups_right_negative;
    logic upper_carry_left, upper_carry_right;
    (* preserve, dont_retime *) logic signed [24:0] left_sum, right_sum, left_carry, right_carry;
    logic signed [24:0] numerator_left, numerator_right;
    wire [24:0] left_term=25'(weighted_left), right_term=25'(weighted_right);
    wire [24:0] next_left_sum=left_sum^left_carry^left_term;
    wire [24:0] next_right_sum=right_sum^right_carry^right_term;
    wire [24:0] next_left_carry=((left_sum&left_carry)|(left_sum&left_term)|(left_carry&left_term))<<1;
    wire [24:0] next_right_carry=((right_sum&right_carry)|(right_sum&right_term)|(right_carry&right_term))<<1;
    (* preserve, dont_retime *) logic [24:0] boundary_left_sum,boundary_right_sum,boundary_left_carry,boundary_right_carry;
    (* preserve, dont_retime *) logic [28:0] boundary_left_groups,boundary_right_groups;
    logic boundary_valid, boundary_groups_valid;
    logic [23:0] magnitude_left, magnitude_right;
    logic magnitude_left_negative, magnitude_right_negative, product_left_negative, product_right_negative;
    logic [47:0] quotient_left, quotient_right;
    logic [23:0] partial_left [0:3], partial_right [0:3];
    (* preserve, dont_merge *) logic [11:0] dsp_left [0:3], dsp_right [0:3];
    logic operand_left_negative, operand_right_negative;
    logic [24:0] middle_left, middle_right;
    logic [47:0] outer_left, outer_right;
    logic [23:0] upper_left, upper_right;
    logic carry_left, carry_right;
    logic partial_left_negative, partial_right_negative, combined_left_negative, combined_right_negative;
    logic middle_valid,middle_left_negative,middle_right_negative;
    (* preserve, dont_retime *) logic [27:0] middle_left_groups,middle_right_groups;
    logic [47:0] middle_outer_left,middle_outer_right;
    logic halves_left_negative, halves_right_negative;
    assign weight=phase>311 ? 7'(9'd375-phase) : 7'd64;
    assign remainder=boundary ? 7'(phase-9'd311) : 7'd0;
    assign boundary=phase>=311;
    function automatic logic [24:0] add25(input logic [24:0] a,b);
        logic [6:0] group_sum [0:3];
        logic [3:0] generate_carry,propagate_carry,carry_in;
        logic [24:0] result;
        for (int group=0;group<4;group++) begin
            group_sum[group]={1'b0,a[group*6+:6]}+{1'b0,b[group*6+:6]};
            generate_carry[group]=group_sum[group][6];
            propagate_carry[group]=&(a[group*6+:6]^b[group*6+:6]);
        end
        carry_in[0]=0;
        carry_in[1]=generate_carry[0];
        carry_in[2]=generate_carry[1] | (propagate_carry[1] && generate_carry[0]);
        carry_in[3]=generate_carry[2] | (propagate_carry[2] && generate_carry[1]) |
            (propagate_carry[2] && propagate_carry[1] && generate_carry[0]);
        for (int group=0;group<4;group++)
            result[group*6+:6]=6'(group_sum[group][5:0]+6'(carry_in[group]));
        result[24]=a[24]^b[24]^(generate_carry[3] | (propagate_carry[3] && carry_in[3]));
        return result;
    endfunction
    function automatic logic [24:0] combine_middle(input logic [27:0] sums);
        logic [3:0] carry_in,propagate;
        logic [24:0] result;
        for (int group=0;group<4;group++) propagate[group]=&sums[group*7+:6];
        carry_in[0]=0;
        carry_in[1]=sums[6];
        carry_in[2]=sums[13] | (propagate[1] && sums[6]);
        carry_in[3]=sums[20] | (propagate[2] && sums[13]) | (propagate[2] && propagate[1] && sums[6]);
        for (int group=0;group<4;group++) result[group*6+:6]=6'(sums[group*7+:6]+6'(carry_in[group]));
        result[24]=sums[27] | (propagate[3] && carry_in[3]);
        return result;
    endfunction
    function automatic logic [24:0] combine_boundary(input logic [28:0] sums);
        logic [24:0] result;
        result=combine_middle(sums[27:0]);
        result[24]=result[24]^sums[28];
        return result;
    endfunction
    function automatic logic carry12(input logic [11:0] a,b);
        logic [6:0] low,high;
        low={1'b0,a[5:0]}+{1'b0,b[5:0]};
        high={1'b0,a[11:6]}+{1'b0,b[11:6]};
        return high[6] | ((&(a[11:6]^b[11:6])) && low[6]);
    endfunction
    function automatic logic [23:0] add_carry24(input logic [23:0] value,input logic carry);
        logic [23:0] result;
        result[5:0]=6'(value[5:0]+6'(carry));
        result[11:6]=6'(value[11:6]+6'(carry && &value[5:0]));
        result[17:12]=6'(value[17:12]+6'(carry && &value[11:0]));
        result[23:18]=6'(value[23:18]+6'(carry && &value[17:0]));
        return result;
    endfunction

    // Each DSP owns its input registers. Unconditional registers let Quartus
    // pack both ends into the multiplier; validity controls downstream use.
    always_ff @(posedge clk) begin
        staged_left<=sample_left;staged_right<=sample_right;
        staged_weight<=weight;staged_remainder<=remainder;
        sample_operand[0]<=staged_left;sample_operand[1]<=staged_right;
        sample_operand[2]<=staged_left;sample_operand[3]<=staged_right;
        coefficient[0]<=staged_weight;coefficient[1]<=staged_weight;
        coefficient[2]<=staged_remainder;coefficient[3]<=staged_remainder;
        weighted_left_dsp<=23'(sample_operand[0])*$signed({1'b0,coefficient[0]});
        weighted_right_dsp<=23'(sample_operand[1])*$signed({1'b0,coefficient[1]});
        remainder_left_dsp<=23'(sample_operand[2])*$signed({1'b0,coefficient[2]});
        remainder_right_dsp<=23'(sample_operand[3])*$signed({1'b0,coefficient[3]});
        weighted_left<=weighted_left_dsp;weighted_right<=weighted_right_dsp;
        remainder_left<=remainder_left_dsp;remainder_right<=remainder_right_dsp;
        for (int part=0;part<4;part++) begin
            dsp_left[part]<=part<2 ? magnitude_left[11:0] : magnitude_left[23:12];
            dsp_right[part]<=part<2 ? magnitude_right[11:0] : magnitude_right[23:12];
            if (part[0]) begin
                partial_left[part]<=dsp_left[part]*24'd2796;partial_right[part]<=dsp_right[part]*24'd2796;
            end else begin
                partial_left[part]<=dsp_left[part]*24'd831;partial_right[part]<=dsp_right[part]*24'd831;
            end
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            phase<=0;left_sum<=0;right_sum<=0;output_valid<=0;output_left<=0;output_right<=0;
            left_carry<=0;right_carry<=0;boundary_valid<=0;boundary_groups_valid<=0;
            boundary_left_sum<=0;boundary_right_sum<=0;boundary_left_carry<=0;boundary_right_carry<=0;
            boundary_left_groups<=0;boundary_right_groups<=0;
            weighted_valid<=0;weighted_boundary<=0;dsp_valid<=0;dsp_boundary<=0;sum_valid<=0;magnitude_valid<=0;product_valid<=0;
            input_valid<=0;input_boundary<=0;staged_valid<=0;staged_boundary<=0;
            numerator_left<=0;numerator_right<=0;magnitude_left<=0;magnitude_right<=0;
            magnitude_left_negative<=0;magnitude_right_negative<=0;product_left_negative<=0;product_right_negative<=0;
            quotient_left<=0;quotient_right<=0;
            operand_valid<=0;operand_left_negative<=0;operand_right_negative<=0;partial_valid<=0;combined_valid<=0;halves_valid<=0;
            middle_left<=0;middle_right<=0;outer_left<=0;outer_right<=0;upper_left<=0;upper_right<=0;
            upper_left_groups<=0;upper_right_groups<=0;upper_groups_valid<=0;
            upper_groups_left_negative<=0;upper_groups_right_negative<=0;upper_carry_left<=0;upper_carry_right<=0;
            carry_left<=0;carry_right<=0;partial_left_negative<=0;partial_right_negative<=0;
            combined_left_negative<=0;combined_right_negative<=0;halves_left_negative<=0;halves_right_negative<=0;
            middle_valid<=0;middle_left_negative<=0;middle_right_negative<=0;
            middle_left_groups<=0;middle_right_groups<=0;middle_outer_left<=0;middle_outer_right<=0;
        end else begin
            staged_valid<=sample_valid;staged_boundary<=boundary;
            input_valid<=staged_valid;input_boundary<=staged_boundary;
            if (sample_valid) begin
                phase<=boundary ? phase-9'd311 : {3'(phase[8:6]+3'd1),phase[5:0]};
            end
            dsp_valid<=input_valid;dsp_boundary<=input_boundary;
            weighted_valid<=dsp_valid;weighted_boundary<=dsp_boundary;
            boundary_valid<=weighted_valid && weighted_boundary;
            boundary_groups_valid<=boundary_valid;
            sum_valid<=boundary_groups_valid;
            boundary_left_sum<=next_left_sum;boundary_right_sum<=next_right_sum;
            boundary_left_carry<=next_left_carry;boundary_right_carry<=next_right_carry;
            for (int group=0;group<4;group++) begin
                boundary_left_groups[group*7+:7]<={1'b0,boundary_left_sum[group*6+:6]}+{1'b0,boundary_left_carry[group*6+:6]};
                boundary_right_groups[group*7+:7]<={1'b0,boundary_right_sum[group*6+:6]}+{1'b0,boundary_right_carry[group*6+:6]};
            end
            boundary_left_groups[28]<=boundary_left_sum[24]^boundary_left_carry[24];
            boundary_right_groups[28]<=boundary_right_sum[24]^boundary_right_carry[24];
            numerator_left<=combine_boundary(boundary_left_groups);numerator_right<=combine_boundary(boundary_right_groups);
            if (weighted_valid) begin
                if (weighted_boundary) begin
                    left_sum<=25'(remainder_left);right_sum<=25'(remainder_right);
                    left_carry<=0;right_carry<=0;
                end else begin
                    left_sum<=next_left_sum;right_sum<=next_right_sum;
                    left_carry<=next_left_carry;right_carry<=next_right_carry;
                end
            end
            magnitude_valid<=sum_valid;
            if (sum_valid) begin
                magnitude_left<=numerator_left<0 ? 24'(-numerator_left) : 24'(numerator_left);
                magnitude_right<=numerator_right<0 ? 24'(-numerator_right) : 24'(numerator_right);
                magnitude_left_negative<=numerator_left<0;magnitude_right_negative<=numerator_right<0;
            end
            // ceil(2^32/375) = 2796*2^12+831. Four 12-bit products
            // keep multiplication in the fast DSP mode; assembly is pipelined.
            operand_valid<=magnitude_valid;
            operand_left_negative<=magnitude_left_negative;operand_right_negative<=magnitude_right_negative;
            partial_valid<=operand_valid;
            partial_left_negative<=operand_left_negative;partial_right_negative<=operand_right_negative;
            middle_valid<=partial_valid;
            middle_left_negative<=partial_left_negative;middle_right_negative<=partial_right_negative;
            for (int group=0;group<4;group++) begin
                middle_left_groups[group*7+:7]<={1'b0,partial_left[1][group*6+:6]}+{1'b0,partial_left[2][group*6+:6]};
                middle_right_groups[group*7+:7]<={1'b0,partial_right[1][group*6+:6]}+{1'b0,partial_right[2][group*6+:6]};
            end
            middle_outer_left<={partial_left[3],partial_left[0]};middle_outer_right<={partial_right[3],partial_right[0]};
            combined_valid<=middle_valid;
            middle_left<=combine_middle(middle_left_groups);middle_right<=combine_middle(middle_right_groups);
            outer_left<=middle_outer_left;outer_right<=middle_outer_right;
            combined_left_negative<=middle_left_negative;combined_right_negative<=middle_right_negative;
            upper_groups_valid<=combined_valid;
            carry_left<=carry12(outer_left[23:12],middle_left[11:0]);
            carry_right<=carry12(outer_right[23:12],middle_right[11:0]);
            for (int group=0;group<4;group++) begin
                upper_left_groups[group*7+:7]<={1'b0,outer_left[24+group*6+:6]}+{1'b0,6'(middle_left[24:12]>>(group*6))};
                upper_right_groups[group*7+:7]<={1'b0,outer_right[24+group*6+:6]}+{1'b0,6'(middle_right[24:12]>>(group*6))};
            end
            upper_groups_left_negative<=combined_left_negative;upper_groups_right_negative<=combined_right_negative;
            halves_valid<=upper_groups_valid;
            upper_left<=24'(combine_middle(upper_left_groups));upper_right<=24'(combine_middle(upper_right_groups));
            upper_carry_left<=carry_left;upper_carry_right<=carry_right;
            halves_left_negative<=upper_groups_left_negative;halves_right_negative<=upper_groups_right_negative;
            product_valid<=halves_valid;
            quotient_left<={add_carry24(upper_left,upper_carry_left),24'b0};
            quotient_right<={add_carry24(upper_right,upper_carry_right),24'b0};
            product_left_negative<=halves_left_negative;product_right_negative<=halves_right_negative;
            output_valid<=product_valid;
            if (product_valid) begin
                output_left<=product_left_negative ? 16'd0-quotient_left[47:32] : quotient_left[47:32];
                output_right<=product_right_negative ? 16'd0-quotient_right[47:32] : quotient_right[47:32];
            end
        end
    end
endmodule
