// Include inside a module. One slot per supported static CC (filter power/type share one).
localparam STATIC_CC_COUNT=40;
function [7:0] static_cc_id;
 input [5:0] slot;
 begin case(slot)
  6'd0: static_cc_id=`PARAM_ID_MASTER_VOL;
  6'd1: static_cc_id=`PARAM_ID_FLT_PAN;
  6'd2: static_cc_id=`PARAM_ID_OSCA_POWER;
  6'd3: static_cc_id=`PARAM_ID_OSCA_WAVE;
  6'd4: static_cc_id=`PARAM_ID_OSCA_UNISON;
  6'd5: static_cc_id=`PARAM_ID_OSCA_DETUNE;
  6'd6: static_cc_id=`PARAM_ID_OSCA_PHASE;
  6'd7: static_cc_id=`PARAM_ID_OSCA_RAND;
  6'd8: static_cc_id=`PARAM_ID_OSCA_WT_POS;
  6'd9: static_cc_id=`PARAM_ID_OSCA_WARP;
  6'd10: static_cc_id=`PARAM_ID_OSCA_PAN;
  6'd11: static_cc_id=`PARAM_ID_OSCA_VOL;
  6'd12: static_cc_id=`PARAM_ID_OSCB_POWER;
  6'd13: static_cc_id=`PARAM_ID_OSCB_WAVE;
  6'd14: static_cc_id=`PARAM_ID_OSCB_UNISON;
  6'd15: static_cc_id=`PARAM_ID_OSCB_DETUNE;
  6'd16: static_cc_id=`PARAM_ID_OSCB_PHASE;
  6'd17: static_cc_id=`PARAM_ID_OSCB_RAND;
  6'd18: static_cc_id=`PARAM_ID_OSCB_WT_POS;
  6'd19: static_cc_id=`PARAM_ID_OSCB_WARP;
  6'd20: static_cc_id=`PARAM_ID_OSCB_PAN;
  6'd21: static_cc_id=`PARAM_ID_OSCB_VOL;
  6'd22: static_cc_id=`PARAM_ID_FLT_TYPE;
  6'd23: static_cc_id=`PARAM_ID_FLT_CUTOFF;
  6'd24: static_cc_id=`PARAM_ID_FLT_RES;
  6'd25: static_cc_id=`PARAM_ID_FLT_MIX;
  6'd26: static_cc_id=`PARAM_ID_ENV1_ATTACK;
  6'd27: static_cc_id=`PARAM_ID_ENV1_DECAY;
  6'd28: static_cc_id=`PARAM_ID_ENV1_SUSTAIN;
  6'd29: static_cc_id=`PARAM_ID_ENV1_RELEASE;
  6'd30: static_cc_id=`PARAM_ID_ENV2_ATTACK;
  6'd31: static_cc_id=`PARAM_ID_ENV2_DECAY;
  6'd32: static_cc_id=`PARAM_ID_ENV2_SUSTAIN;
  6'd33: static_cc_id=`PARAM_ID_ENV2_RELEASE;
  6'd34: static_cc_id=`PARAM_ID_DELAY_FEEDBACK;
  6'd35: static_cc_id=`PARAM_ID_DELAY_TIME;
  6'd36: static_cc_id=`PARAM_ID_DELAY_MIX;
  6'd37: static_cc_id=`PARAM_ID_REVERB_SIZE;
  6'd38: static_cc_id=`PARAM_ID_REVERB_DECAY;
  6'd39: static_cc_id=`PARAM_ID_REVERB_MIX;
  default: static_cc_id=0;
 endcase end
endfunction
