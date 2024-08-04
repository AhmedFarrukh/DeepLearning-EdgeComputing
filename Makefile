# List of markdown files
MARKDOWNS := reserve.md raspberry_pi_inference.md

# Convert markdown filenames to notebook filenames
NOTEBOOKS := $(MARKDOWNS:.md=.ipynb)

# Default target to build all notebooks
all: $(NOTEBOOKS)

# Clean target to remove generated notebooks
clean:
	rm -f reserve.ipynb raspberry_pi_inference.ipynb

# Pattern rule to convert markdown to notebook
%.ipynb: %.md
	pandoc --wrap=none $< -o $@