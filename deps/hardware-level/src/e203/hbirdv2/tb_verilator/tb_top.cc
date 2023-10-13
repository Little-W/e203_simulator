#include "Vtb_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <iostream>
#include <string>

#ifdef JTAGVPI
#include "jtagServer.h"
#endif

vluint64_t tick = 0;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_top *soc = new Vtb_top;

    // check if trace is enabled
    int trace_en = 0;
    for (int i = 0; i < argc; i++)
    {
        if (strcmp(argv[i], "-t") == 0)
            trace_en = 1;
        if (strcmp(argv[i], "--trace") == 0)
            trace_en = 1;
    }

    if (trace_en)
    {
        std::cout << "Trace is enabled.\n";
    }
    else
    {
        std::cout << "Trace is disabled.\n";
    }
#ifdef JTAGVPI
        VerilatorJtagServer* jtag = new VerilatorJtagServer(10);
        jtag->init_jtag_server(5555, false);
    #endif
    //enable waveform
    VerilatedVcdC* tfp = new VerilatedVcdC;
    if (trace_en)
    {
        Verilated::traceEverOn(true);
        soc->trace(tfp, 99); // Trace 99 levels of hierarchy
        tfp->open("tb_top.vcd");
    }

    soc->clk = 0;
    soc->rst_n = 0;
    soc->eval();
    if (trace_en) tfp->dump(tick); tick++;

    // enough time to reset
    for (int i = 0; i < 500; i++)
    {
        soc->clk = !soc->clk;
        soc->eval();
        if (trace_en)
            tfp->dump(tick);
        tick++;
    }

    soc->rst_n = 1;
    soc->eval();

    for (int i = 0; i < 5000; i++)
    {
        soc->clk = !soc->clk;
        soc->eval();
        if (trace_en)
            tfp->dump(tick);
        tick++;
    }

    while (!Verilated::gotFinish())
    {
        soc->clk = !soc->clk;
        soc->eval();
#ifdef JTAGVPI
        jtag->doJTAG(tick, &soc->tms_i, &soc->tdi_i, &soc->tck_i, soc->tdo_o);
#endif
        if (trace_en)
            tfp->dump(tick);
        tick++;
    }

    if (trace_en)
    {
        tfp->close();
    }
    delete soc;

    return 0;
}
