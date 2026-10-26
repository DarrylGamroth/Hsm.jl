using Hsm

# Execute the current README block. The original broken snapshot and its
# failure are retained in the baseline review commit and result log.
include(joinpath(pkgdir(Hsm), "test", "test_readme_examples.jl"))
