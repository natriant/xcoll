import numpy as np
from ._everest import lib
from .random import set_rutherford_parameters


# def rutherford(t, zatom, emr):
#     cnorm  = 2.607e-5
#     cnform = 0.8561e3
#     return (cnorm*np.exp(((-1*t)*cnform)*emr**2)) * (zatom/t)**2


def scatter(*, npart, x_part, xp_part, y_part, yp_part, s_part, p_part, part_hit,
                part_abs, part_impact, part_indiv, part_linteract, nabs_type,linside, run_exenergy, run_anuc, run_zatom,
                run_emr, run_rho,  run_hcut, run_bnref, run_csref0, run_csref1, run_csref5,run_radl, run_dlri, 
                run_dlyi, run_eum, run_ai, run_collnt, run_cprob, run_xintl, run_bn, run_ecmsq, run_xln15s, run_bpp, is_crystal, 
                c_length, c_rotation, c_aperture, c_offset, c_tilt, c_enom, onesided, length, material, csect,
                cry_tilt, cry_rcurv, cry_bend, cry_alayer, cry_xmax, cry_ymax, cry_orient, cry_miscut, cry_cBend, 
                cry_sBend, cry_cpTilt, cry_spTilt, cry_cnTilt, cry_snTilt
        ):

    set_rutherford_parameters(zatom=run_zatom, emr=run_emr, hcut=run_hcut)
  
    # Initilaisation
    length  = c_length
    p0 = c_enom

    x0 = 0
    xp0 = 0

    nhit   = 0
    nabs   = 0
    fracab = 0
    mirror = 1

    cprob0 = run_cprob[0]
    cprob1 = run_cprob[1]
    cprob2 = run_cprob[2]
    cprob3 = run_cprob[3]
    cprob4 = run_cprob[4]
    cprob5 = run_cprob[5]

    # Compute rotation factors for collimator rotation
    cRot   = np.cos(c_rotation)
    sRot   = np.sin(c_rotation)
    cRRot  = np.cos(-c_rotation)
    sRRot  = np.sin(-c_rotation)

    # Set energy and nucleon change variables as with the coupling
    # ien0, ien1: particle energy entering/leaving the collimator
    # energy in MeV
    nnuc0 = 0
    ien0  = 0
    nnuc1 = 0
    ien1  = 0

    # Crystal tracking parameters
    iProc       = 0
    n_chan      = 0
    n_VR        = 0
    n_amorphous = 0
    s_imp        = 0

    for i in range(npart):

        val_part_hit = part_hit[i]
        val_part_abs = part_abs[i]
        val_part_impact = part_impact[i]
        val_part_indiv = part_indiv[i]
        val_part_linteract = part_linteract[i]
        val_nabs_type = nabs_type[i]
        val_linside = linside[i]

        if (val_part_abs != 0):
            continue

        x_in = x_part[i]
        xp_in = xp_part[i]
        y_in = y_part[i]
        yp_in = yp_part[i]
        s_in = s_part[i]
        p_in = p_part[i]
        
        val_part_impact = -1
        val_part_linteract = -1
        val_part_indiv = -1

        x = x_in
        xp = xp_in
        xp_in0 = xp_in
        z = y_in
        zp = yp_in
        p = p_in
        sp = 0
        dpop = (p - p0)/p0

        # Transform particle coordinates to get into collimator coordinate  system
        # First do rotation into collimator frame
        x  =  x_in*cRot + sRot*y_in
        z  =  y_in*cRot - sRot*x_in
        xp = xp_in*cRot + sRot*yp_in
        zp = yp_in*cRot - sRot*xp_in
        
        # For one-sided collimators consider only positive X. For negative X jump to the next particle
        if (onesided & (x < 0)):
            continue

        # Log input energy + nucleons as per the FLUKA coupling
        nnuc0   = nnuc0 + 1
        ien0    = ien0 + p_in * 1.0e3

        # Now mirror at the horizontal axis for negative X offset
        if (x < 0):
            mirror    = -1
            tiltangle = -1*c_tilt[1]
        else:
            mirror    = 1
            tiltangle = c_tilt[0]
    
        x  = mirror*x
        xp = mirror*xp

        # Shift with opening and offset
        x = (x - c_aperture/2) - mirror*c_offset

        # Include collimator tilt
        if(tiltangle > 0):
            xp = xp - tiltangle
        
        if(tiltangle < 0):
            x  = x + np.sin(tiltangle) * c_length
            xp = xp - tiltangle

        # particle passing above the jaw are discarded => take new event
        # entering by the face, shorten the length (zlm) and keep track of
        # entrance longitudinal coordinate (keeps) for histograms

        # The definition is that the collimator jaw is at x>=0.

        # 1) Check whether particle hits the collimator
        isimp = False
        s     = 0
        zlm = -1*length


        if (is_crystal):

            
            crystal_result = lib.crystal(x,
                                        xp,
                                        z,
                                        zp,
                                        s,
                                        p,
                                        x0,
                                        xp0,
                                        zlm,
                                        s_imp,
                                        isimp,
                                        val_part_hit, 
                                        val_part_abs, 
                                        val_part_impact, 
                                        val_part_indiv, 
                                        c_length, 
                                        run_exenergy, 
                                        run_rho, 
                                        run_anuc, 
                                        run_zatom, 
                                        run_emr, 
                                        run_dlri, 
                                        run_dlyi, 
                                        run_ai, 
                                        run_eum, 
                                        run_collnt,                                                                                                                             
                                        run_hcut, 
                                        run_bnref, 
                                        run_csref0, 
                                        run_csref1, 
                                        run_csref5,                                                                                                                             
                                        nhit, 
                                        nabs,
                                        cry_tilt,
                                        cry_rcurv,
                                        cry_bend,
                                        cry_alayer,
                                        cry_xmax,
                                        cry_ymax,
                                        cry_orient,
                                        cry_miscut,
                                        cry_cBend,
                                        cry_sBend,
                                        cry_cpTilt,
                                        cry_spTilt,
                                        cry_cnTilt,
                                        cry_snTilt,
                                        iProc,
                                        n_chan,
                                        n_VR,
                                        n_amorphous
                                        )


            val_part_hit = crystal_result[0]
            val_part_abs = crystal_result[1]
            val_part_impact = crystal_result[2]
            val_part_indiv = crystal_result[3]
            nhit = crystal_result[4]
            nabs = crystal_result[5]
            s_imp = crystal_result[6]
            isimp = crystal_result[7]
            s = crystal_result[8]
            zlm = crystal_result[9]
            x = crystal_result[10]
            xp = crystal_result[11]
            x0 = crystal_result[12]
            xp0 = crystal_result[13]
            z = crystal_result[14]
            zp = crystal_result[15]
            p = crystal_result[16]
            iProc = crystal_result[17]
            n_chan = crystal_result[18]
            n_VR = crystal_result[19]
            n_amorphous = crystal_result[20]

            if (isimp==1):
                isimp==True
            else:
                isimp==False

            if (nabs != 0):
                val_part_abs = 1
                val_part_linteract = zlm

            s_imp  = (s - c_length) + s_imp


##################################################################################################

        else:

            if (x >= 0):
            # Particle hits collimator and we assume interaction length ZLM equal
            # to collimator length (what if it would leave collimator after
            # small length due to angle???)
                zlm  = length
                val_part_impact = x
                val_part_indiv  = xp
            
            elif (xp <= 0):
            # Particle does not hit collimator. Interaction length ZLM is zero.
                zlm = 0
            
            else:
            # Calculate s-coordinate of interaction point
                s = (-1*x)/xp
            
                if (s < length):
                    zlm = length - s
                    val_part_impact = 0
                    val_part_indiv  = xp
                else:
                    zlm = 0
           

            # First do the drift part
            # DRIFT PART
            drift_length = length - zlm
            if (drift_length > 0):
                x  = x  + xp * drift_length
                z  = z  + zp * drift_length
                sp = sp + drift_length

            # Now do the scattering part
            if (zlm > 0):
                if (not val_linside):
                # first time particle hits collimator: entering jaw
                    val_linside = True

                s_impact = sp
                nhit = nhit + 1

                
                jaw_result = lib.jaw(run_exenergy,
                                run_anuc,
                                run_zatom,
                                run_rho,
                                run_radl,
                                cprob0,
                                cprob1,
                                cprob2,
                                cprob3,
                                cprob4,
                                cprob5,
                                run_xintl,
                                run_bn,
                                run_ecmsq,
                                run_xln15s,
                                run_bpp,
                                p0,
                                nabs,
                                s,
                                zlm,
                                x,
                                xp,
                                z,
                                zp,
                                dpop)

                run_exenergy = jaw_result[0]
                run_bn = jaw_result[1]
                p0 = jaw_result[2]
                nabs = jaw_result[3]
                s = jaw_result[4]
                zlm = jaw_result[5]
                x = jaw_result[6]
                xp = jaw_result[7]
                z = jaw_result[8]
                zp = jaw_result[9]
                dpop = jaw_result[10]

                val_nabs_type = nabs
                val_part_hit  = 1

                isimp = True
                # simp  = s_impact

                # Writeout should be done for both inelastic and single diffractive. doing all transformations
                # in x_flk and making the set to 99.99 mm conditional for nabs=1
                if (nabs == 1 or nabs == 4):
                # Transform back to lab system for writeout.
                # keep x,y,xp,yp unchanged for continued tracking, store lab system variables in x_flk etc

                # Finally, the actual coordinate change to 99 mm
                    if (nabs == 1):
                        fracab = fracab + 1
                        x = 99.99e-3
                        z = 99.99e-3
                        val_part_linteract = zlm
                        val_part_abs = 1
                    # Collimator jaw interaction

            if (nabs != 1 and zlm > 0):
            # Do the rest drift, if particle left collimator early
                drift_length = (length-(s+sp))

                if (drift_length > 1.0e-15):
                    val_linside = False
                    x  = x  + xp * drift_length
                    z  = z  + zp * drift_length
                    sp = sp + drift_length
            
                val_part_linteract = zlm - drift_length
            
####################################################################################################################

        # Transform back to particle coordinates with opening and offset
        if(x < 99.0e-3):
            # Include collimator tilt
            if(tiltangle > 0):
                x  = x  + tiltangle*c_length
                xp = xp + tiltangle
            elif(tiltangle < 0):
                x  = x  + tiltangle*c_length
                xp = xp + tiltangle
                x  = x  - np.sin(tiltangle) * c_length

            # Transform back to particle coordinates with opening and offset
            x   = (x + c_aperture/2) + mirror*c_offset

            # Now mirror at the horizontal axis for negative X offset
            x  = mirror * x
            xp = mirror * xp

            # Last do rotation into collimator frame
            x_in  =  x*cRRot +  z*sRRot
            y_in  =  z*cRRot -  x*sRRot
            xp_in = xp*cRRot + zp*sRRot
            yp_in = zp*cRRot - xp*sRRot

            # Log output energy + nucleons as per the FLUKA coupling
            # Do not log dead particles
            nnuc1       = nnuc1 + 1                           # outcoming nucleons
            ien1        = ien1  + p_in * 1e3                 # outcoming energy

            if(is_crystal):
                p_in = p
                s_in = s_in + s
            else:
                p_in = (1 + dpop) * p0
                s_in = sp

        else:
            x_in = x
            y_in = z

        x_part[i] = x_in
        xp_part[i] = xp_in
        y_part[i] = y_in
        yp_part[i] = yp_in
        s_part[i] = s_in
        p_part[i] = p_in
        part_hit[i] = val_part_hit
        part_abs[i] = val_part_abs
        part_impact[i] = val_part_impact
        part_indiv[i] = val_part_indiv
        part_linteract[i] = val_part_linteract
        nabs_type[i] = val_nabs_type
        linside[i] = val_linside
