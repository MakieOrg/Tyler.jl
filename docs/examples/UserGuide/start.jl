# # Quick start into Tyler

# ## A basic request

using Tyler, GLMakie

m = Tyler.Map(Rect2f(-0.0921, 51.5, 0.04, 0.025))
m.figure # we should wait for the update/fetch of tiles before showing/saving the figure

# !!! info 
#       This is just a test
#       ok?