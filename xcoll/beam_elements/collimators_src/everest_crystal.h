#ifndef XCOLL_EVEREST_CRYSTAL_H
#define XCOLL_EVEREST_CRYSTAL_H

#include <math.h>

// TODO:
//    Do not split 4d and zeta in drifts
//    Use drift function from xtrack Drift element (call its C function)

/*gpufun*/
void cry_drift_6d(LocalParticle* part0, double length) {
    //start_per_particle_block (part0->part)
        double const rpp    = LocalParticle_get_rpp(part);
        double const rv0v   = 1./LocalParticle_get_rvv(part);
        double const xp     = LocalParticle_get_px(part) * rpp;
        double const yp     = LocalParticle_get_py(part) * rpp;
        double const dzeta  = 1 - rv0v * ( 1. + ( xp*xp + yp*yp ) / 2. );

        LocalParticle_add_to_x(part, xp * length );
        LocalParticle_add_to_y(part, yp * length );
        LocalParticle_add_to_s(part, length);
        LocalParticle_add_to_zeta(part, length * dzeta );
    //end_per_particle_block
}

// TODO: 
// Write impacts



/*gpufun*/
void track_crystal(EverestCrystalData el, LocalParticle* part0) {

    double const energy0 = LocalParticle_get_energy0(&part0[0]) / 1e9; // Reference energy in GeV

    // Material properties
    CrystalMaterialData material = EverestCrystalData_getp_material(el);
    double const zatom    = CrystalMaterialData_get_Z(material);
    double const anuc     = CrystalMaterialData_get_A(material);
    double const rho      = CrystalMaterialData_get_density(material);
    double const exenergy = CrystalMaterialData_get_excitation_energy(material);
    double const emr      = CrystalMaterialData_get_nuclear_radius(material);
    double const bnref    = CrystalMaterialData_get_nuclear_elastic_slope(material);
    double const csref0   = CrystalMaterialData_get_cross_section(material, 0);
    double const csref1   = CrystalMaterialData_get_cross_section(material, 1);
    double const csref5   = CrystalMaterialData_get_cross_section(material, 5);
    double const hcut     = CrystalMaterialData_get_hcut(material);
    double const dlri     = CrystalMaterialData_get_crystal_radiation_length(material);
    double const dlyi     = CrystalMaterialData_get_crystal_nuclear_length(material);
    double const eUm      = CrystalMaterialData_get_crystal_potential(material);
    double const ai       = CrystalMaterialData_get_crystal_plane_distance(material);
    double const collnt   = CrystalMaterialData_get_nuclear_collision_length(material);

    // Calculate scattering parameters
    struct ScatteringParameters scat = calculate_scattering(energy0,anuc,rho,zatom,emr,csref0,csref1,csref5,bnref);
    set_rutherford_parameters(zatom, emr, hcut);

    //start_per_particle_block (part0->part)

        scatter_cry(el, part, scat,
                exenergy,
                anuc,
                zatom,
                emr,
                rho,
                hcut,
                bnref,
                csref0,
                csref1,
                csref5,
                0,   // radl not used
                dlri,
                dlyi,
                eUm,
                ai,
                collnt,
                1    // is_crystal
        );
    //end_per_particle_block
}

/*gpufun*/
void EverestCrystal_track_local_particle(EverestCrystalData el, LocalParticle* part0) {
    int8_t const is_active      = EverestCrystalData_get__active(el);
    double const inactive_front = EverestCrystalData_get_inactive_front(el);
    double const active_length  = EverestCrystalData_get_active_length(el);
    double const inactive_back  = EverestCrystalData_get_inactive_back(el);

    if (!is_active){
        // Drift full length
        cry_drift_6d(part0, inactive_front+active_length+inactive_back);
    } else {
        cry_drift_6d(part0, inactive_front);
        track_crystal(el, part0);
        cry_drift_6d(part0, inactive_back);
    }
}

#endif
