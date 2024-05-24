using Test, GenFSM_resources_init_fr

out = plusTwo(3)

@test out == 5
