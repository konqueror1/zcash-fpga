/*
  Copyright (C) 2019  Benjamin Devlin and Zcash Foundation

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
`timescale 1ps/1ps

module ec_fp2_point_add_tb ();
import common_pkg::*;
import bls12_381_pkg::*;

localparam CLK_PERIOD = 1000;

logic clk, rst;

if_axi_stream #(.DAT_BYTS(($bits(fp2_jb_point_t)*2+7)/8)) in_if(clk); // Two points
if_axi_stream #(.DAT_BYTS(($bits(fp2_jb_point_t)+7)/8)) out_if(clk);

if_axi_stream #(.DAT_BITS(2*bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) mult_in_if(clk);
if_axi_stream #(.DAT_BITS(bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) mult_out_if(clk);

if_axi_stream #(.DAT_BITS(2*bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) add_in_if(clk);
if_axi_stream #(.DAT_BITS(bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) add_out_if(clk);

if_axi_stream #(.DAT_BITS(2*bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) sub_in_if(clk);
if_axi_stream #(.DAT_BITS(bls12_381_pkg::DAT_BITS), .CTL_BITS(16)) sub_out_if(clk);

fp2_jb_point_t in_p1, in_p2, out_p;

always_comb begin
  in_p1 = in_if.dat[0 +: $bits(fp2_jb_point_t)];
  in_p2 = in_if.dat[$bits(fp2_jb_point_t) +: $bits(fp2_jb_point_t)];
  out_if.dat = out_p;
end

initial begin
  rst = 0;
  repeat(2) #(20*CLK_PERIOD) rst = ~rst;
end

initial begin
  clk = 0;
  forever #CLK_PERIOD clk = ~clk;
end

always_comb begin
  out_if.sop = 1;
  out_if.eop = 1;
  out_if.ctl = 0;
  out_if.mod = 0;
end

// Check for errors
always_ff @ (posedge clk)
  if (out_if.val && out_if.err)
    $error(1, "%m %t ERROR: output .err asserted", $time);

ec_fp2_point_add #(
  .FP2_TYPE ( fp2_jb_point_t ),
  .FE_TYPE  ( fe_t           ),
  .FE2_TYPE ( fe2_t          )
)
ec_fp2_point_add (
  .i_clk ( clk ),
  .i_rst ( rst ),
    // Input points
  .i_p1  ( in_p1      ),
  .i_p2  ( in_p2      ),
  .i_val ( in_if.val  ),
  .o_rdy ( in_if.rdy  ),
  .o_p   ( out_p      ),
  .o_err ( out_if.err ),
  .i_rdy ( out_if.rdy ),
  .o_val ( out_if.val ) ,
  .o_mul_if ( mult_in_if ),
  .i_mul_if ( mult_out_if ),
  .o_add_if ( add_in_if ),
  .i_add_if ( add_out_if ),
  .o_sub_if ( sub_in_if ),
  .i_sub_if ( sub_out_if )
);

always_comb begin
  mult_out_if.sop = 1;
  mult_out_if.eop = 1;
  mult_out_if.err = 0;
  mult_out_if.mod = 1;

  add_out_if.sop = 1;
  add_out_if.eop = 1;
  add_out_if.err = 0;
  add_out_if.mod = 1;

  sub_out_if.sop = 1;
  sub_out_if.eop = 1;
  sub_out_if.err = 0;
  sub_out_if.mod = 1;
end


// Attach a mod reduction unit and multiply - mod unit
ec_fp_mult_mod #(
  .P             ( P   ),
  .KARATSUBA_LVL ( 3   ),
  .CTL_BITS      ( 16  )
)
ec_fp_mult_mod (
  .i_clk( clk         ),
  .i_rst( rst         ),
  .i_dat_a ( mult_in_if.dat[0 +: bls12_381_pkg::DAT_BITS] ),
  .i_dat_b ( mult_in_if.dat[bls12_381_pkg::DAT_BITS +: bls12_381_pkg::DAT_BITS] ),
  .i_val ( mult_in_if.val ),
  .i_ctl ( mult_in_if.ctl ),
  .o_rdy ( mult_in_if.rdy ),
  .o_dat ( mult_out_if.dat ),
  .i_rdy ( mult_out_if.rdy ),
  .o_val ( mult_out_if.val ),
  .o_ctl ( mult_out_if.ctl )
);

adder_pipe # (
  .BITS     ( bls12_381_pkg::DAT_BITS ),
  .P        ( P   ),
  .CTL_BITS ( 16  ),
  .LEVEL    ( 2   )
)
adder_pipe (
  .i_clk ( clk        ),
  .i_rst ( rst        ),
  .i_dat_a ( add_in_if.dat[0 +: bls12_381_pkg::DAT_BITS] ),
  .i_dat_b ( add_in_if.dat[bls12_381_pkg::DAT_BITS +: bls12_381_pkg::DAT_BITS] ),
  .i_ctl ( add_in_if.ctl ),
  .i_val ( add_in_if.val  ),
  .o_rdy ( add_in_if.rdy  ),
  .o_dat ( add_out_if.dat ),
  .o_val ( add_out_if.val ),
  .o_ctl ( add_out_if.ctl ),
  .i_rdy ( add_out_if.rdy )
);

subtractor_pipe # (
  .BITS     ( bls12_381_pkg::DAT_BITS ),
  .P        ( P   ),
  .CTL_BITS ( 16  ),
  .LEVEL    ( 2   )
)
subtractor_pipe (
  .i_clk ( clk        ),
  .i_rst ( rst        ),
  .i_dat_a ( sub_in_if.dat[0 +: bls12_381_pkg::DAT_BITS] ),
  .i_dat_b ( sub_in_if.dat[bls12_381_pkg::DAT_BITS +: bls12_381_pkg::DAT_BITS] ),
  .i_ctl ( sub_in_if.ctl ),
  .i_val ( sub_in_if.val  ),
  .o_rdy ( sub_in_if.rdy  ),
  .o_dat ( sub_out_if.dat ),
  .o_val ( sub_out_if.val ),
  .o_ctl ( sub_out_if.ctl ),
  .i_rdy ( sub_out_if.rdy )
);

task test(input fp2_jb_point_t p1, p2, p_exp);
begin
  integer signed get_len;
  logic [common_pkg::MAX_SIM_BYTS*8-1:0] expected,  get_dat;
  fp2_jb_point_t p_out;
  $display("Running test ...");


  fork
    in_if.put_stream({p2, p1}, ((2*$bits(fp2_jb_point_t)+7)/8));
    out_if.get_stream(get_dat, get_len);
  join

  p_out = get_dat;

  $display("Expected:");
  print_fp2_jb_point(p_exp);
  $display("Was:");
  print_fp2_jb_point(p_out);

  if (p_exp != p_out) begin
    $fatal(1, "%m %t ERROR: test_0 point was wrong", $time);
  end

  $display("test PASSED");

end
endtask;

fp2_jb_point_t one_point = '{x:FE2_one, y:FE2_one, z:FE2_one};
fp2_jb_point_t two_point = '{x:'{c1:381'd2, c0:381'd2}, y:'{c1:381'd2, c0:381'd2}, z:FE2_one};

fp2_jb_point_t g2_point_dbl = '{x:'{c0:381'd2004569552561385659566932407633616698939912674197491321901037400001042336021538860336682240104624979660689237563240,
         c1:381'd3955604752108186662342584665293438104124851975447411601471797343177761394177049673802376047736772242152530202962941},
         y:'{c0:381'd978142457653236052983988388396292566217089069272380812666116929298652861694202207333864830606577192738105844024927,
         c1:381'd2248711152455689790114026331322133133284196260289964969465268080325775757898907753181154992709229860715480504777099},
         z:'{c0:381'd3145673658656250241340817105688138628074744674635286712244193301767486380727788868972774468795689607869551989918920,
         c1:381'd968254395890002185853925600926112283510369004782031018144050081533668188797348331621250985545304947843412000516197}};

initial begin
  out_if.rdy = 0;
  in_if.val = 0;
  #(40*CLK_PERIOD);

 test(g2_point, g2_point_dbl, add_fp2_jb_point(g2_point, g2_point_dbl)
     /*'{x:'{c0:381'd2260316515795278483227354417550273673937385151660885802822200676798473320332386191812885909324314180009401590033496,
        c1:381'd3157705674295752746643045744187038651144673626385096899515739718638356953289853357506730468806346866010850469607484},
        y:'{c0:381'd3116406908094559010983016654096953279342014296159903648784769141704444407188785914041577477129027384530629024324101,
        c1:381'd624739198846365065958511422206549337298084868949577950118937104460230094422413163466712508875838914229203179007739},
        z:'{c0:381'd1372365362697527824661960056804989242334959973433633343888520294361286317391588271032081626721722944066233963018813,
        c1:381'd135340553306575460225879133388402231094623862625345515492709522456301372944095308361691014711792956665222682354141}}*/);

  #1us $finish();
end
endmodule