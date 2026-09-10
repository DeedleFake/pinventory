defmodule Pinventory.Repo.Migrations.WallsAsRowsDropFloorPlans do
  use Ecto.Migration

  def up do
    create table(:walls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :floor_id, references(:floors, type: :binary_id, on_delete: :delete_all), null: false

      add :x1, :float, null: false
      add :y1, :float, null: false
      add :x2, :float, null: false
      add :y2, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:walls, [:floor_id])

    flush()

    migrate_json_walls_to_rows()

    drop_if_exists index(:floors, [:floor_plan_id, :position])
    drop_if_exists index(:floors, [:floor_plan_id])

    alter table(:floors) do
      remove :walls
      remove :floor_plan_id
    end

    drop table(:floor_plans)
  end

  def down do
    create table(:floor_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :singleton_key, :string, null: false, default: "default"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:floor_plans, [:singleton_key])

    alter table(:floors) do
      add :walls, :json, null: false, default: "[]"
      add :floor_plan_id, references(:floor_plans, type: :binary_id, on_delete: :delete_all)
    end

    create index(:floors, [:floor_plan_id])
    create index(:floors, [:floor_plan_id, :position])

    flush()

    restore_floor_plans_and_json_walls()

    drop table(:walls)
  end

  defp migrate_json_walls_to_rows do
    %{rows: rows} = repo().query!("SELECT id, walls FROM floors")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.flat_map(rows, fn [floor_id, walls_raw] ->
        Enum.map(decode_walls(walls_raw), fn wall ->
          %{
            id: Ecto.UUID.generate(),
            floor_id: floor_id,
            x1: wall_coord(wall, "x1"),
            y1: wall_coord(wall, "y1"),
            x2: wall_coord(wall, "x2"),
            y2: wall_coord(wall, "y2"),
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    if entries != [] do
      repo().insert_all("walls", entries)
    end
  end

  defp restore_floor_plans_and_json_walls do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    %{rows: floor_rows} = repo().query!("SELECT id FROM floors")

    if floor_rows != [] do
      plan_id = Ecto.UUID.generate()

      repo().insert_all("floor_plans", [
        %{
          id: plan_id,
          singleton_key: "default",
          inserted_at: now,
          updated_at: now
        }
      ])

      for [floor_id] <- floor_rows do
        %{rows: wall_rows} =
          repo().query!(
            "SELECT x1, y1, x2, y2 FROM walls WHERE floor_id = ? ORDER BY inserted_at, id",
            [floor_id]
          )

        walls_json =
          wall_rows
          |> Enum.map(fn [x1, y1, x2, y2] ->
            %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}
          end)
          |> Jason.encode!()

        repo().query!(
          "UPDATE floors SET floor_plan_id = ?, walls = ? WHERE id = ?",
          [plan_id, walls_json, floor_id]
        )
      end
    end
  end

  defp decode_walls(nil), do: []

  defp decode_walls(walls) when is_binary(walls) do
    case Jason.decode(walls) do
      {:ok, decoded} -> decode_walls(decoded)
      _ -> []
    end
  end

  defp decode_walls(walls) when is_list(walls) do
    Enum.flat_map(walls, fn
      wall when is_map(wall) -> [wall]
      wall when is_binary(wall) -> decode_walls(wall)
      _ -> []
    end)
  end

  defp decode_walls(wall) when is_map(wall), do: [wall]
  defp decode_walls(_), do: []

  defp wall_coord(wall, key) when is_map(wall) do
    value = Map.get(wall, key) || Map.get(wall, atom_key(key))
    clamp_unit(value)
  end

  defp atom_key("x1"), do: :x1
  defp atom_key("y1"), do: :y1
  defp atom_key("x2"), do: :x2
  defp atom_key("y2"), do: :y2

  defp clamp_unit(n) when is_float(n), do: n
  defp clamp_unit(n) when is_integer(n), do: n * 1.0

  defp clamp_unit(n) when is_binary(n) do
    case Float.parse(n) do
      {parsed, _} -> parsed
      :error -> 0.0
    end
  end

  defp clamp_unit(_), do: 0.0
end
