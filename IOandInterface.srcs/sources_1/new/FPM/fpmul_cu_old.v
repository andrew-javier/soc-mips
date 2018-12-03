module fpmul_cu (
    input wire clk,
    input wire rst,
    
    input wire Start,
    
    //output ctrl signals to dp
    output reg SA_LD,
    output reg EA_LD,
    output reg MA_LD,
    output reg SB_LD,
    output reg EB_LD,
    output reg MB_LD,
    output reg SP_LD,
    output reg EP_SET, //set to FF, necessary for exit conditions such as if abnormal
    output reg EP_RST, //set to 00
    output reg [1:0] EP_SEL, //at certain points, need to select either ep - 127, ep + 1, or ea + eb inputs
    output reg EP_LD,
    output reg MPH_SET,
    output reg MPH_RST,
    output reg [2:0] MPH_SEL, //sel between MP[47:24], {MPH[22:0], MPL[23]}, MPH + 1, and 0x800000
    output reg MPH_LD,
    output reg MPL_SEL, //sel between MP[23:0] or MPL << 1 for state 5
    output reg MPL_LD,
    output reg UF_RST,
    output reg UF_LD, 
    output reg OF_RST,
    output reg OF_LD,
    output reg P_RST,
    output reg P_LD,
    
    //status signals
    input wire NaN,
    input wire Inf,
    input wire Zero, 
    input wire MPH23,
    input wire Round,
    input wire Carry,
    input wire UFlow,
    input wire OFlow,
    
    //top-level outputs
    output reg Done
);

//states
localparam [3:0]
    S0 = 4'b0000,
    S1 = 4'b0001,
    S2 = 4'b0010,
    S3 = 4'b0011,
    S4 = 4'b0100,
    S5 = 4'b0101,
    S6 = 4'b0110,
    S7 = 4'b0111,
    S8 = 4'b1000,
    S9 = 4'b1001;
    
reg [3:0] state; // State is the CS

wire Normal;

assign Normal = ~(NaN | Inf | Zero); //1 if all operand flags are zero

//assign intReset = (rst | ~(|state[3:0]));// ds change

//update state
always @ (posedge clk, posedge rst) // ds change
begin
    		/**
		 * State 0 is the same as reset!, therefore rst | (state == S0)
		 * Reset product, underflow/overflow, NaN, Inf and ZF
		 */
		if (rst) begin
			// Turn off all state signal
			SA_LD 	<= 1'b0;
			EA_LD 	<= 1'b0;
			MA_LD 	<= 1'b0;
			SB_LD 	<= 1'b0;
			EB_LD 	<= 1'b0;
			MB_LD 	<= 1'b0;
			SP_LD 	<= 1'b0;
			EP_RST 	<= 1'b1;
			EP_SET 	<= 1'b0;
			EP_SEL 	<= 2'b00;
			EP_LD 	<= 1'b0;
			MPH_SET <= 1'b0;
			MPH_SEL <= 3'b000;
			MPH_RST <= 1'b1;
			MPH_LD 	<= 1'b0;
			MPL_SEL <= 1'b0;
			MPL_LD 	<= 1'b0;
			UF_LD 	<= 1'b0;
			OF_LD 	<= 1'b0;
			P_LD 	<= 1'b0;
			Done 	<= 1'b0;
			///
			OF_RST 	<= 1'b1;
			UF_RST 	<= 1'b1;
			P_RST 	<= 1'b1;
			///
			state <= S1;
		end
		else begin
			case(state)
				S1 :  //load in all operand registers
				begin
					// Turn off previous state signal
					EP_RST 	<= 1'b0;
					MPH_RST <= 1'b0;
					OF_RST 	<= 1'b0;
					UF_RST 	<= 1'b0;
					P_RST 	<= 1'b0;
					///
					SA_LD <= 1'b1;
					EA_LD <= 1'b1;
					MA_LD <= 1'b1;
					SB_LD <= 1'b1;
					EB_LD <= 1'b1;
					MB_LD <= 1'b1;
					///
					if (Start) begin
						state <= S2;
					end
				end
				S2 : 
				begin
					// Turn off previous state signal
					SA_LD <= 1'b0;
					EA_LD <= 1'b0;
					MA_LD <= 1'b0;
					SB_LD <= 1'b0;
					EB_LD <= 1'b0;
					MB_LD <= 1'b0;
					///
					SP_LD 	<= 1'b1;
					EP_SEL 	<= 2'b00; //select ea + eb to load into ep reg
					EP_LD 	<= 1'b1; 
					///
					state <= S3;
				end
				S3 : 
				begin
					// Turn off previous state signal
					SP_LD <= 1'b0;
					///
					EP_SEL <= 2'b10; //select ep - 127 to load into ep reg
					EP_LD <= 1'b1; 
					
					///
					state <= S4;
				end
				S4 : 
				begin
					// Turn off previous state signal
					EP_SEL <= 2'b00;
					EP_LD <= 1'b0;
					///
					if(NaN) begin
						EP_SET <= 1'b1;
						MPH_SET <= 1'b1;
					end
					else if (Inf) begin
						EP_SET <= 1'b1;
						MPH_RST <= 1'b1;
					end
					else if (Zero) begin
						EP_RST <= 1'b1;
						MPH_RST <= 1'b1;
					end
					else begin //end of 3-cycle multiplication cycle
						MPH_LD <= 1'b1;
						MPL_LD <= 1'b1;
					end
					
					///
					if (Normal) begin
						state <= S8;
					end
					else begin
						state <= S5;
					end
				end
				S5 :
				begin
					// Turn off previous state signal
					EP_SET <= 1'b0;
					EP_RST <= 1'b0;
					MPH_SET <= 1'b0;
					MPH_RST <= 1'b0;
					///
					if(MPH23) begin
						// Turn off previous state signal
						MPH_LD <= 1'b0;
						MPL_LD <= 1'b0;
						///
						EP_SEL <= 2'b01; //select ep + 1 to load into ep reg
						EP_LD <= 1'b1;
					end
					else begin
						MPH_SEL <= 3'b001; //select {MPH[22:0], MPL[23]} to load into mph reg
						MPH_LD <= 1'b1;
						MPL_SEL <= 1'b1; //select MPL << 1 to load into mpl reg
						MPL_LD <= 1'b1;
					end
					///
					state <= S6;
				end
				S6 :
				begin
					// Turn off previous state signal
					MPL_SEL <= 1'b0;
					MPL_LD <= 1'b0;
					///
					if(Round & ~Carry) begin
						// Turn off previous state signal
						EP_SEL <= 2'b00;
						EP_LD <= 1'b0;
						///
						MPH_SEL <= 3'b010; //select mph + 1 to load into mph reg
						MPH_LD <= 1'b1;
					end
					else if (Round & Carry) begin
						MPH_SEL <= 3'b100; //select 0x800000 to load into mph reg
						EP_SEL <= 2'b01; //select ep + 1 to load into ep reg
						MPH_LD <= 1'b1;
						EP_LD <= 1'b1;
					end 
					else begin
						// Turn off previous state signal
						EP_SEL <= 2'b00;
						EP_LD <= 1'b0;
						MPL_SEL <= 1'b0;
						MPH_SEL <= 3'b000;
						MPH_LD <= 1'b0;
						///
					end
					///
					state <= S7;
				end
				S7 :
				begin
					// Turn off previous state signal
					MPH_SEL <= 3'b000;
					MPH_LD <= 1'b0;
					EP_SEL <= 2'b00; //select ep + 1 to load into ep reg
					MPH_LD <= 1'b0;
					EP_LD <= 1'b0;
					///
					if (~UFlow & ~OFlow) begin
						UF_RST <= 1'b1;
						OF_RST <= 1'b1;
					end
					if (~UFlow & OFlow) begin
						UF_RST <= 1'b1;
						OF_LD <= 1'b1;
						EP_SET <= 1'b1; //set ep[7:0] to 0xff
						MPH_RST <= 1'b1;
					end
					if (UFlow & ~OFlow) begin
						UF_LD <= 1'b1;
						OF_RST <= 1'b1;
						EP_RST <= 1'b1;
						MPH_RST <= 1'b1;
					end
					///
					state <= S8;
				end
				S8 : //package the product and load product abnormal flags
				begin
					// Turn off previous state signal
					UF_RST <= 1'b0;
					OF_RST <= 1'b0;
					UF_LD <= 1'b0;
					OF_LD <= 1'b0;
					EP_SET <= 1'b0;
					MPH_RST <= 1'b0;
					///
					P_LD <= 1'b1;
					///
					state <= S9;
				end
				S9 : //signal completion of the computation
				begin
					// Turn off previous state signal
					P_LD <= 1'b0;
					///
					Done <= 1'b1;
					///
					state <= S0;
				end
			endcase
		end
end

endmodule
