if not FilterCinematicName then
    return
end

local kBlockedCinematics = set
{
    "cinematics/marine/exo_flamer/flame.cinematic",
    "cinematics/marine/exo_flamer/flame_1p.cinematic",
    "cinematics/marine/exo_flamer/flame_residue_1p_part1.cinematic",
    "cinematics/marine/exo_flamer/flame_residue_1p_part2.cinematic",
    "cinematics/marine/exo_flamer/flame_trail_1p_part2.cinematic",
    "cinematics/marine/exo_flamer/flame_trail_1p_part3.cinematic",
    "cinematics/marine/exo_flamer/flame_trail_part2.cinematic",
    "cinematics/marine/exo_flamer/flame_trail_part3.cinematic",
}

local oldFilterCinematicName = FilterCinematicName
function FilterCinematicName(cinematicName)

    if Client.kMinimalParticles and kBlockedCinematics[cinematicName] then
        return "cinematics/minimal/blank.cinematic"
    end

    return oldFilterCinematicName(cinematicName)

end
