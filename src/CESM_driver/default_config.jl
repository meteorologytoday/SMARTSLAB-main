println("===== Default library, config BEGIN =====")
include("julia_lib/MailboxPipe.jl")
include("julia_lib/BinaryIO.jl")
include("julia_lib/NetCDFIO.jl")
include("julia_lib/parseMsg.jl")

using Formatting
using Printf
using JSON
using .MailboxPipe
using .BinaryIO
using .NetCDFIO

wdir = "."
caseroot    = "."

domain_file = "/home/tienyiah/cesm_inputdata/cesm1/share/domains/domain.ocn.gx3v7.120323.nc"

zs = collect(Float64, range(0, -500, step=-5))
K = 1e-5


println("===== Default library, config END =====")

