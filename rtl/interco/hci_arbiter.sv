/*
 * hci_arbiter.sv
 * Francesco Conti <f.conti@unibo.it>
 * Tobias Riedener <tobiasri@student.ethz.ch>
 *
 * Copyright (C) 2019-2020 ETH Zurich, University of Bologna
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * The shallow interconnect multiplexes two sets of TCDM channels
 * with a fixed-priority scheme: the high priority port is always granted.
 * It is designed to be deployed directly at the boundary with embedded
 * memories (SRAMs or SCMs). It will not wprk if used in another condition!
 */
 
import hci_package::*;

module hci_arbiter
#(
  parameter int unsigned NB_CHAN = 2
)
(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  hci_interconnect_ctrl_t ctrl_i,

  hci_core_intf.target    in_high    [0:NB_CHAN-1],
  hci_core_intf.target    in_low     [0:NB_CHAN-1],
  hci_core_intf.initiator out        [0:NB_CHAN-1]
);

  logic [NB_CHAN-1:0] hs_req_in;
  logic [NB_CHAN-1:0] ls_req_in;
  logic [NB_CHAN-1:0] hs_pass_d;
  logic hs_req_d;
  logic ls_req_d;
  logic switch_channels_d;
  logic unsigned [7:0] ls_stall_ctr_d;

  // priority_req is the OR of all requests coming out of the log interconnect.
  // it should be simplified to simply an OR of all requests coming *into* the
  // log interconnect directly within the synthesis tool.
  always_comb
  begin
    hs_req_d = |hs_req_in;
    ls_req_d = |ls_req_in;
    if (ctrl_i.low_prio_max_stall > 0) //Set to 0 to disable this functionality
    begin
      if (ls_stall_ctr_d >= ctrl_i.low_prio_max_stall)
        hs_req_d = 0; //Let low side through for once
    end
  end
  
  //Low side stall counter
	always_ff @(posedge clk_i or negedge rst_ni)
	begin
		if (~rst_ni)
			ls_stall_ctr_d <= 0;
		else if (hs_req_d & ls_req_d)
			ls_stall_ctr_d <= ls_stall_ctr_d + 1;
    else
			ls_stall_ctr_d <= 0;
	end
  
  assign switch_channels_d = ctrl_i.hwpe_prio;

  // Req mapping
  generate
    for(genvar ii=0; ii<NB_CHAN; ii++) begin: req_mapping

      // switch_channels_d could switch priorities -> in_low is priority request
      always_comb
      begin
        if (switch_channels_d)
        begin
          ls_req_in[ii] = in_high[ii].req;
          hs_req_in[ii] = in_low[ii].req;
        end
        else 
        begin
          hs_req_in[ii] = in_high[ii].req;
          ls_req_in[ii] = in_low[ii].req;
        end
      end
    end // req_mapping
  endgenerate

  // Side select
  generate
    for(genvar ii=0; ii<NB_CHAN; ii++) begin: side_select
      assign hs_pass_d[ii] = (hs_req_d & hs_req_in[ii]) ^ switch_channels_d;
    end // side_select
  endgenerate

  // tcdm ports binding
  generate
    for(genvar ii=0; ii<NB_CHAN; ii++) begin: tcdm_binding
      always_comb
      begin
        in_high[ii].gnt = '0;
        in_low [ii].gnt = '0;
        if(hs_pass_d[ii]) 
        begin
          out[ii].req     = in_high[ii].req;
          out[ii].add     = in_high[ii].add;
          out[ii].wen     = in_high[ii].wen;
          out[ii].be      = in_high[ii].be;
          out[ii].data    = in_high[ii].data;
          out[ii].id      = in_high[ii].id;
          out[ii].user    = in_high[ii].user;
          out[ii].ecc     = in_high[ii].ecc;
          in_high[ii].gnt = out[ii].gnt;
        end 
        else
        begin
          out[ii].req    = in_low[ii].req;
          out[ii].add    = in_low[ii].add;
          out[ii].wen    = in_low[ii].wen;
          out[ii].be     = in_low[ii].be;
          out[ii].data   = in_low[ii].data;
          out[ii].id     = in_low[ii].id;
          out[ii].user   = in_low[ii].user;
          out[ii].ecc    = in_low[ii].ecc;
          in_low[ii].gnt = out[ii].gnt;
        end
        in_high[ii].r_data = out[ii].r_data;
        in_low [ii].r_data = out[ii].r_data;
        in_high[ii].r_id   = out[ii].r_id;
        in_low [ii].r_id   = out[ii].r_id;
        in_high[ii].r_user = out[ii].r_user;
        in_low [ii].r_user = out[ii].r_user;
        in_high[ii].r_ecc  = out[ii].r_ecc;
        in_low [ii].r_ecc  = out[ii].r_ecc;
        // r_valid signals are NOT propagated by the arbiter, they are generated at
        // routing stage. In previous HCI versions, we used a r_valid-less version
        // of the protocol here.
        in_high[ii].r_valid = '0;
        in_low [ii].r_valid = '0;
      end
    end // tcdm_binding
  endgenerate

endmodule // hci_arbiter
