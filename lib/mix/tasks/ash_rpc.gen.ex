defmodule Mix.Tasks.AshRpc.Gen do
  @moduledoc """
  Generate a minimal TypeScript declaration for the Ash RPC router.

      mix ash_rpc.gen --output=./frontend/generated

  Options:
    --output - directory to write `trpc.d.ts` (required)
    --domains - comma-separated domain modules (optional)

  If --domains is not provided, tries to locate modules that expose `domains/0`
  (i.e. modules using `AshRpc.Router`) and uses those.
  """
  use Mix.Task

  alias AshRpc.TypeScript.{Generator, ResourceUtils}

  @shortdoc "Generate Ash RPC TS types"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, switches: [output: :string, domains: :string, zod: :boolean])

    output_dir = opts[:output] || abort!("--output is required")

    domains =
      case opts[:domains] do
        nil ->
          case ResourceUtils.find_router_module() do
            {:ok, domains} -> domains
            {:error, msg} -> abort!(msg)
          end
        str ->
          str |> String.split([",", " "], trim: true) |> Enum.map(&Module.concat([&1]))
      end

    unless File.dir?(output_dir) do
      File.mkdir_p!(output_dir)
    end

    # Generate TypeScript types using the new modular system
    v11_types = Generator.generate_types(domains)
    out_file = Path.join(output_dir, "trpc.d.ts")
    File.write!(out_file, v11_types)
    Mix.shell().info([:green, "Wrote ", out_file])

    if opts[:zod] do
      zod_ts = Generator.generate_zod_schemas(domains)
      zod_file = Path.join(output_dir, "trpc.zod.ts")
      File.write!(zod_file, zod_ts)
      Mix.shell().info([:green, "Wrote ", zod_file])
    end
  end

  defp abort!(msg) do
    Mix.raise("ash_rpc.gen: #{msg}")
  end
end
