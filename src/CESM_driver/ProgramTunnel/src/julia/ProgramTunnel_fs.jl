
module ProgramTunnel_fs
using Formatting

export ProgramTunnelInfo, hello, recvText, sendText, reverseRole!

mutable struct ProgramTunnelInfo

    recv_fn    :: AbstractString
    send_fn    :: AbstractString
    lock_fn    :: AbstractString
    chk_freq   :: AbstractFloat
    timeout    :: AbstractFloat
    timeout_limit_cnt :: Integer
    ests       :: Dict
    buffer_cnt :: Integer

    function ProgramTunnelInfo(;
        recv          :: AbstractString     = "ProgramTunnel-Y2X.txt",
        send          :: AbstractString     = "ProgramTunnel-X2Y.txt",
        lock          :: AbstractString     = "ProgramTunnel-lock.txt",
        chk_freq      :: AbstractFloat                  = 0.05,
        path          :: Union{AbstractString, Nothing} = nothing,
        timeout       :: AbstractFloat                  = 10.0,
        buffer        :: AbstractFloat                  = 0.1,
        tag_and_init  :: Any = [ (:default, 0.0) ],
    )

        if chk_freq <= 0.0
            ErrorException("chk_freq must be positive.") |> throw
        end
        ests = Dict()
        for (tag, init) in tag_and_init
            ests[tag] = Estimator(init, ceil(init/chk_freq))
        end

        PTI = new(
            recv,
            send,
            lock,
            chk_freq,
            timeout,
            ceil(timeout / chk_freq),
            ests,
            ceil(buffer / chk_freq),
        )

        if path != nothing
            appendPath(PTI, path)
        end

        return PTI
    end
end

mutable struct Estimator
    first_sleep :: AbstractFloat
    first_cnt   :: Integer
end

function appendPath(PTI::ProgramTunnelInfo, path::AbstractString)
    PTI.recv_fn = joinpath(path, PTI.recv_fn)
    PTI.send_fn = joinpath(path, PTI.send_fn)
    PTI.lock_fn = joinpath(path, PTI.lock_fn)
end

function reverseRole!(PTI::ProgramTunnelInfo)
    PTI.recv_fn, PTI.send_fn = PTI.send_fn, PTI.recv_fn
end

function lock(
    fn::Function,
    PTI::ProgramTunnelInfo,
)

    if obtainLock(PTI)
        fn()
        releaseLock(PTI)
    else
        ErrorException("Lock cannot be obtained before timeout.") |> throw
    end
end


function obtainLock(PTI::ProgramTunnelInfo)

    for cnt in 1:PTI.timeout_limit_cnt
        if ! isfile(PTI.lock_fn)

            try
                open(PTI.lock_fn, "w") do io
                end
                return true
            catch
                # do nothing
            end

        end

        sleep(PTI.chk_freq)
    end

    return false
end

function releaseLock(PTI::ProgramTunnelInfo)
    rm(PTI.lock_fn, force=true)
end

function recvText(PTI::ProgramTunnelInfo, tag::Symbol=:default)
    local result

    get_through = false
    est = PTI.ests[tag]

    sleep(est.first_sleep)

    if isfile(PTI.recv_fn)
        est.first_sleep -= PTI.chk_freq
        est.first_sleep = max(0.0, est.first_sleep)
        get_through = true

        println("[", string(tag) ,"] Message is already there. Adjust first_sleep to : ", est.first_sleep)
    else
        for cnt in 1:(PTI.timeout_limit_cnt - est.first_cnt)

            sleep(PTI.chk_freq)

            if isfile(PTI.recv_fn)
                get_through = true
                # Out of buffer, need to adjust: increase est.first_sleep
                println(cnt, "; ", PTI.buffer_cnt)
                if cnt > PTI.buffer_cnt
                    est.first_sleep += PTI.chk_freq 
                    println("[", string(tag), "] Out of buffer. Adjust first_sleep to : ", est.first_sleep)
                end
                break
            end

        end
    end

    if ! get_through
        ErrorException("No further incoming message within timeout.") |> throw
    end

    lock(PTI) do
        open(PTI.recv_fn, "r") do io
            result = strip(read(io, String))
        end

        rm(PTI.recv_fn, force=true)
        releaseLock(PTI)

    end

    return result
end

function sendText(PTI::ProgramTunnelInfo, msg::AbstractString)

    lock(PTI) do
        open(PTI.send_fn, "w") do io
            write(io, msg)
        end
    end
end


#=
function hello(PTI::ProgramTunnelInfo; max_try::Integer=default_max_try)
    send(PTI, "<<TEST>>", max_try)
    recv_msg = recv(PTI, max_try) 
    if recv_msg != "<<TEST>>"
        throw(ErrorException("Weird message: " * recv_msg))
    end
end
=#

end
