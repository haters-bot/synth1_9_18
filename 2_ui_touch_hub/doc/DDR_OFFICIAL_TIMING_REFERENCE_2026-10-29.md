# DDR3 clock constraints: official reference review (2026-10-29)

## Sources actually inspected

- Gowin DDR3 official IP page: https://www.gowinsemi.com/en/support/ip_detail/14/
- Official reference ZIP: https://www.gowinsemi.com/upload/database_doc/2010/document/67cebaccb9842.zip
- Official user guide: https://www.gowinsemi.com/upload/database_doc/2009/document/696a8c052f84e.pdf
- Downloaded originals, extracted SDC and SHA256 review:
  `impl/ddr_official_reference_20261029_145035/`.

The release-note download on that page describes the old 2018 GW2A release;
it is not a suitable source for GW5AST-138B timing constraints. The reference
ZIP itself includes a dedicated `DDR3_MC_PHY_1vs4_5a138k` example. Its project
selects `GW5AST-138B`, `GW5AST-LV138FPG676AES`, and `gw5ast138b-002`.
Its encrypted DDR source header identifies Gowin V1.9.11.01, 2025-02-28.
The UI machine uses V1.9.11.03 Education; the imported UI DDR source identifies
V1.9.12.03. The reference is evidence for the clock-boundary convention, not
proof that every version or DRAM parameter is interchangeable.

## Exact reference boundary

Reference entry:
`Gowin_DDR3_Memory_Interface_RefDesign/DDR3_MC_PHY_1vs4_5a138k/project/src/ddr3_1v4_hs.sdc`

The reference declares 400 MHz on `memory_clk`, 100 MHz at the controller's
`fclkdiv/CLKOUT`, and a separate reference input clock. It marks all three
clock-domain pairs asynchronous, including the controller user clock versus
the PHY memory clock. These are the vendor IP's prescribed domain boundaries;
they are not equivalent to adding exceptions for individual failing paths.

The UI normal/debug SDC now follows this separation with names
`ddr_clk400` and `ddr_user_clk100`. The UI reference input remains its actual
50 MHz, and its own pixel/serializer clocks remain related to each other.
No OSER10 reset exception or change to clock frequency was added.
Within each DDR clock domain, setup/hold and reset checks remain enabled.
User PCM transactions remain entirely on the 100 MHz controller user port;
their connection to the UI clock uses the existing Gray-pointer FIFOs.

Normal/debug SDC also request expanded global reports plus pixel-only setup
and bit-clock reset reports. The command syntax comes from the installed
`IDE/doc/EN/SUG940-2.0E_Gowin Design Timing Constraints User Guide.pdf`,
section 5.5.1 (PDF pages 83..86). This is a reporting change, not an exception.
The manual explains that the default report contains only 25 paths.

## Why the earlier constraint was wrong

Candidate `R16A_build_20261029_142528` kept the two DDR clocks in the same group.
Its first 25 setup paths are all user-to-PHY crossings: 4 end at a falling
400 MHz edge and 21 at a rising edge. The worst is -7.508 ns, from the IP's
`read_rclksel_conf_2_s0` to `u_dqs`; other reported crossings involve the IP's
calibration/hold registers and input serializers.

Grouping the two clocks as related imposed ordinary edge-to-edge checks on
the vendor's IP boundary, contrary to that device's official example. This
review corrects the earlier handoff instruction to keep them in one group.

## What is still unproven

- No new routed result exists for this constraint correction yet.
- The pixel domain's 45.907 MHz result remains below its 50 MHz requirement.
- Expanded per-domain setup/reset reporting is still needed; a top-25 report
  dominated by DDR crossings cannot establish pixel or all OSER10 reset paths.
- Final combined-CST pin comparison, source hashes and the five timing checks
  must pass on the final source before any deployment.
- Actual DDR calibration, PCB/DRAM settings, usable capacity and whole-song
  recording need board-level acceptance. No bitstream was programmed here.
