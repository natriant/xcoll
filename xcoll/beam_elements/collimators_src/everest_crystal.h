// copyright ############################### #
// This file is part of the Xcoll Package.   #
// Copyright (c) CERN, 2023.                 #
// ######################################### #

#ifndef XCOLL_EVEREST_CRYSTAL_H
#define XCOLL_EVEREST_CRYSTAL_H
#include <math.h>
#include <stdio.h>


/*gpufun*/
void EverestCrystal_track_local_particle(EverestCrystalData el, LocalParticle* part0) {
    int8_t is_active      = EverestCrystalData_get__active(el);
    is_active            *= EverestCrystalData_get__tracking(el);
    double const inactive_front = EverestCrystalData_get_inactive_front(el);
    double const active_length  = EverestCrystalData_get_active_length(el);
    double const inactive_back  = EverestCrystalData_get_inactive_back(el);

    CrystalMaterialData material = EverestCrystalData_getp_material(el);
    RandomRutherfordData rng = EverestCrystalData_getp_rutherford_rng(el);
    RandomRutherfordData_set_by_xcoll_material(rng, (GeneralMaterialData) material);

    // Crystal properties
    double length  = EverestCrystalData_get_active_length(el);
    double const co_x       = EverestCrystalData_get_dx(el);
    double const co_y       = EverestCrystalData_get_dy(el);
    // TODO: use xtrack C-code for rotation element
    double const cRot       = EverestCrystalData_get_cos_z(el);
    double const sRot       = EverestCrystalData_get_sin_z(el);
    // if collimator.jaw_F_L != collimator.jaw_B_L or collimator.jaw_F_R != collimator.jaw_B_R:
    //     raise NotImplementedError
    double const c_aperture = EverestCrystalData_get_jaw_F_L(el) - EverestCrystalData_get_jaw_F_R(el);
    double const c_offset   = EverestCrystalData_get_offset(el) + ( EverestCrystalData_get_jaw_F_L(el) + EverestCrystalData_get_jaw_F_R(el) )/2;
    double const c_tilt0    = EverestCrystalData_get_tilt(el, 0);
    double const c_tilt1    = EverestCrystalData_get_tilt(el, 1);
    double const onesided   = EverestCrystalData_get_onesided(el);
    double const bend       = EverestCrystalData_get_bend(el);
    double const cry_tilt   = EverestCrystalData_get_align_angle(el) + EverestCrystalData_get_crytilt(el);
    double const bend_ang   = length/bend;    // temporary value
    if (cry_tilt >= -bend_ang) {
        length = bend*(sin(bend_ang + cry_tilt) - sin(cry_tilt));
    } else {
        length = bend*(sin(bend_ang - cry_tilt) + sin(cry_tilt));
    }
    double const cry_rcurv  = bend;
    double const cry_bend   = length/cry_rcurv; //final value (with corrected length) 
    double const cry_alayer = EverestCrystalData_get_thick(el);
    double const cry_xmax   = EverestCrystalData_get_xdim(el);
    double const cry_ymax   = EverestCrystalData_get_ydim(el);
    double const cry_orient = EverestCrystalData_get_orient(el);
    double const cry_miscut = EverestCrystalData_get_miscut(el);

    //start_per_particle_block (part0->part)
        if (!is_active){
            // Drift full length
            Drift_single_particle(part, inactive_front+active_length+inactive_back);

        } else {
            // Check collimator initialisation
            int8_t is_tracking = assert_tracking(part, XC_ERR_INVALID_TRACK);
            int8_t rng_set     = assert_rng_set(part, RNG_ERR_SEEDS_NOT_SET);
            int8_t ruth_set    = assert_rutherford_set(rng, part, RNG_ERR_RUTH_NOT_SET);

            if ( is_tracking && rng_set && ruth_set) {
                // Drift inactive front
                Drift_single_particle(part, inactive_front);

                // Scatter

                // Move to closed orbit
                LocalParticle_add_to_x(part, -co_x);
                LocalParticle_add_to_y(part, -co_y);

                scatter_cry(part, length, material, rng, cRot, sRot, c_aperture, c_offset, c_tilt0, c_tilt1, 
                            onesided, cry_tilt, cry_rcurv, cry_bend, cry_alayer, cry_xmax, cry_ymax, cry_orient, 
                            cry_miscut);

                // Return from closed orbit
                LocalParticle_add_to_x(part, co_x);
                LocalParticle_add_to_y(part, co_y);

                // Drift inactive back (only surviving particles)
                if (LocalParticle_get_state(part) > 0){
                    Drift_single_particle(part, inactive_back);
                }
            }
        }
    //end_per_particle_block
}


#endif /* XCOLL_EVEREST_CRYSTAL_H */