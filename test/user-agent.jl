using Test
using Tyler
using Sockets

# A minimal, single-request HTTP server that records the request head it receives,
# so we can check what Tyler actually puts on the wire.
function capture_request(download)
    server = Sockets.listen(Sockets.localhost, 0)
    port = Sockets.getsockname(server)[2]
    head = String[]
    serving = @async begin
        socket = Sockets.accept(server)
        while true
            line = readline(socket)
            isempty(line) && break
            push!(head, line)
        end
        write(socket, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
        close(socket)
    end
    try
        download("http://$(Sockets.localhost):$port/0/0/0")
        wait(serving)
    finally
        close(server)
    end
    return head
end

user_agents(head) = [strip(chopprefix(line, "User-Agent:")) for line in head if startswith(line, "User-Agent:")]

struct UserAgentProvider <: Tyler.TileProviders.AbstractProvider end
Tyler.file_ending(::UserAgentProvider) = ".png"

@testset "User-Agent" begin
    @test Tyler.USER_AGENT[] == "Tyler.jl/$(Base.pkgversion(Tyler)) (+https://github.com/MakieOrg/Tyler.jl)"

    @testset "ByteDownloader" begin
        head = capture_request() do url
            Tyler.download_tile_data(Tyler.ByteDownloader(), UserAgentProvider(), url)
        end
        @test user_agents(head) == [Tyler.USER_AGENT[]]
    end

    @testset "PathDownloader" begin
        head = mktempdir() do cache_dir
            capture_request() do url
                Tyler.download_tile_data(Tyler.PathDownloader(cache_dir), UserAgentProvider(), url)
            end
        end
        @test user_agents(head) == [Tyler.USER_AGENT[]]
    end

    @testset "Override" begin
        agent = "TylerTests/1.0 (+https://github.com/MakieOrg/Tyler.jl)"
        head = capture_request() do url
            Tyler.download_tile_data(Tyler.ByteDownloader(; user_agent=agent), UserAgentProvider(), url)
        end
        @test user_agents(head) == [agent]
    end
end
