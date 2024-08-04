# List of markdown files
MARKDOWNS := reserve.md reserve_edge.md

# Convert markdown filenames to notebook filenames
NOTEBOOKS := $(MARKDOWNS:.md=.ipynb)

# Default target to build all notebooks
all: $(NOTEBOOKS)

# Clean target to remove generated notebooks
clean:
	rm -f reserve.ipynb reserve_edge.ipynb

# Pattern rule to convert markdown to notebook
%.ipynb: %.md
	pandoc --wrap=none $< -o $@