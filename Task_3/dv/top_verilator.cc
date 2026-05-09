#include <cassert>
#include <fstream>
#include <iostream>

#include "Vtop_verilator__Syms.h"
#include "ibex_pcounts.h"
#include "verilated_toplevel.h"
#include "verilator_memutil.h"
#include "verilator_sim_ctrl.h"

class MySoc {
 public:
  MySoc(const char *ram_hier_path, int ram_size_words);
  virtual ~MySoc() {}
  virtual int Main(int argc, char **argv);


 protected:
  top_verilator _top;
  VerilatorMemUtil _memutil;
  MemArea _ram;

  virtual int Setup(int argc, char **argv, bool &exit_app);
  virtual void Run();
  virtual bool Finish();
};

MySoc::MySoc(const char *ram_hier_path, int ram_size_words)
    : _ram(ram_hier_path, ram_size_words, 4) {}

int MySoc::Main(int argc, char **argv) {
  bool exit_app;
  int ret_code = Setup(argc, argv, exit_app);

  if (exit_app) {
    return ret_code;
  }

  Run();

  if (!Finish()) {
    return 1;
  }

  return 0;
}

int MySoc::Setup(int argc, char **argv, bool &exit_app) {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

  simctrl.SetTop(&_top, &_top.clk_i, &_top.rst_ni,
                 VerilatorSimCtrlFlags::ResetPolarityNegative);

  _memutil.RegisterMemoryArea("ram", 0x100000, &_ram);
  simctrl.RegisterExtension(&_memutil);

  exit_app = false;
  return simctrl.ParseCommandArgs(argc, argv, exit_app);
}

void MySoc::Run() {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

  std::cout << "Simulation of your SoC" << std::endl
            << "======================" << std::endl
            << std::endl;

  simctrl.RunSimulation();
}

bool MySoc::Finish() {
  VerilatorSimCtrl &simctrl = VerilatorSimCtrl::GetInstance();

  if (!simctrl.WasSimulationSuccessful()) {
    return false;
  }

  // Set the scope to the root scope, the ibex_pcount_string function otherwise
  // doesn't know the scope itself. Could be moved to ibex_pcount_string, but
  // would require a way to set the scope name from here, similar to MemUtil.
  svSetScope(svGetScopeFromName("TOP.top_verilator"));

  std::cout << "\nPerformance Counters" << std::endl
            << "====================" << std::endl;
  std::cout << ibex_pcount_string(false);

  std::ofstream pcount_csv("performance_counters.csv");
  pcount_csv << ibex_pcount_string(true);

  return true;
}

int main(int argc, char **argv) {
  MySoc my_soc(
      "TOP.top_verilator.u_soc_mod.u_ram.gen_generic.u_impl_generic",
      32 * 1024 // 32k words = 128 KiB
  );

  return my_soc.Main(argc, argv);
}
