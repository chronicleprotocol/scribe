# Script to plot benchmark results. Result is saved in `benchmarks.png`
#
# Run via:
# ```bash
# $ python script/benchmarks/visualize.py
# ```
import matplotlib.pyplot as plt

# Bar configuration
x = [5, 10, 15, 20, 50, 100, 200, 255]

# Scribe benchmark results received via `run.sh`
scribe = [80280, 105070, 132414, 156983, 314455, 574227, 1096599, 1382810]

# ScribeOptimistic benchmark results received via `run.sh`
opScribe = [68815, 68887, 68944, 69004, 69791, 71186, 73630, 74735]

# Plotting the benchmark data
plt.plot(x, scribe, label='Scribe')
plt.plot(x, opScribe, label='ScribeOptimistic')

# Adjust the margins
plt.subplots_adjust(left=0.2, right=0.9, bottom=0.1, top=0.9)
# Add a legend
plt.legend()

# Adding labels and title
plt.xlabel('number of bar')
plt.ylabel('(op)poke() gas usage')
plt.title('Scribe Benchmark Results')

# Save graph to file
plt.savefig('benchmarks.png')
