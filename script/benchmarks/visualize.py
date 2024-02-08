# Script to plot benchmark results. Result is saved in `benchmarks.png`
#
# Run via:
# ```bash
# $ python script/benchmarks/visualize.py
# ```
import matplotlib.pyplot as plt

# Bar configuration
x = [5, 10, 15, 20, 50, 100, 200, 255]

# Scribe's poke benchmark results received via `relay.sh`
scribe = [80280, 105070, 132414, 156983, 314455, 574227, 1096599, 1382810]

# ScribeOptimistic's opPoke benchmark results received via `relay.sh`
opScribe = [68815, 68887, 68944, 69004, 69791, 71186, 73630, 74735]

# Challenger's opChallenge benchmark results received via `challenger.sh`
challenger = [90374, 115745, 143701, 168848, 330371, 596972, 1132141, 1424857]

# Plotting the benchmark data
plt.plot(x, scribe, label='Scribe')
plt.plot(x, opScribe, label='ScribeOptimistic')
plt.plot(x, challenger, label='Challenger')

# Adjust the margins
plt.subplots_adjust(left=0.2, right=0.9, bottom=0.1, top=0.9)
# Add a legend
plt.legend()

# Adding labels and title
plt.xlabel('number of bar')
plt.ylabel('(op)poke()/opChallenge() gas usage')
plt.title('Relay and Challenger Benchmark Results')

# Save graph to file
plt.savefig('benchmarks.png')
