import numpy as np


class K2Engine:

    def __init__(self, n_alloc, random_generator_seed=None):

        self._n_alloc = n_alloc

        if random_generator_seed is None:
            self.random_generator_seed = np.random.randint(1, 100000)
        else:
            self.random_generator_seed = random_generator_seed

        try:
            import xcoll.beam_elements.pyk2 as pyk2
        except ImportError:
            print("Warning: Failed importing pyK2 (did you compile?)." \
                  + "K2collimators will be installed but are not trackable.")
        else:
            pyk2.pyk2_init(n_alloc=n_alloc, random_generator_seed=self.random_generator_seed)

    @property
    def n_alloc(self):
        return self._n_alloc


class K2Collimator:

    iscollective = True
    isthick = True
    behaves_like_drift = True

    def __init__(self, *, k2engine, active_length, angle, inactive_front=0, inactive_back=0,
                 jaw_F_L=1, jaw_F_R=-1, jaw_B_L=1, jaw_B_R=-1, onesided=False, dx=0, dy=0, dpx=0, dpy=0, offset=0, tilt=[0,0],
                 is_active=True, record_impacts=False, material=None):

        self._k2engine = k2engine
        self.active_length = active_length
        self.inactive_front = inactive_front
        self.inactive_back = inactive_back
        self.angle = angle
        self.jaw_F_L = jaw_F_L
        self.jaw_F_R = jaw_F_R
        self.jaw_B_L = jaw_B_L
        self.jaw_B_R = jaw_B_R
        self.onesided = onesided
        self.dx = dx
        self.dy = dy
        self.dpx = dpx
        self.dpy = dpy
        self.offset = offset
        if hasattr(tilt, '__iter__'):
            if isinstance(tilt, str):
                raise ValueError("Variable tilt has to be a number or array of numbers!")
            elif len(tilt) == 1:
                tilt = [tilt[0], tilt[0]]
        else:
            tilt = [tilt, tilt]
        self.tilt = np.array(tilt, dtype=np.float64)
        self.is_active = is_active
        self.material = material
        self.record_impacts = record_impacts
        self._reset_random_seed = False

    @property
    def k2engine(self):
        return self._k2engine

    @property
    def is_active(self):
        return self._active

    @is_active.setter
    def is_active(self, is_active):
        self._active = is_active
        if not is_active:
            self.jaw_F_L = 1
            self.jaw_F_R = -1
            self.jaw_B_L = 1
            self.jaw_B_R = -1

    def reset_random_seed(self):
        self._reset_random_seed = True

    @property
    def length(self):
        return self.active_length + self.inactive_front + self.inactive_back

    def track(self, particles):  # TODO: write impacts
        import xcoll.beam_elements.pyk2 as pyk2
        npart = particles._num_active_particles
        if npart > self.k2engine.n_alloc:
            raise ValueError(f"Tracking {npart} particles but only {self.k2engine.n_alloc} allocated!")
        if npart == 0:
            return
        if self._reset_random_seed == True:
            reset_seed = self.k2engine.random_generator_seed
            self._reset_random_seed = False
        else:
            reset_seed = -1
        if self.material is None:
            raise ValueError("Cannot track if material is not set!")
        
        if not self.is_active:
            # Drift full length
            L = self.length
            if L > 0:
                rpp = particles.rpp[:npart]
                xp = particles.px[:npart] * rpp
                yp = particles.py[:npart] * rpp
                dzeta = particles.rvv[:npart] - ( 1 + ( xp*xp + yp*yp ) / 2 )
                particles.x[:npart] += xp * L
                particles.y[:npart] += yp * L
                particles.s[:npart] += L
                particles.zeta[:npart] += dzeta*L
        else:
            # Drift inactive front
            L = self.inactive_front
            if L > 0:
                rpp = particles.rpp[:npart]
                xp = particles.px[:npart] * rpp
                yp = particles.py[:npart] * rpp
                dzeta = particles.rvv[:npart] - ( 1 + ( xp*xp + yp*yp ) / 2 )
                particles.x[:npart] += xp * L
                particles.y[:npart] += yp * L
                particles.s[:npart] += L
                particles.zeta[:npart] += dzeta*L

            # Go to collimator reference system (subtract closed orbit)
            x_part = particles.x[:npart] - self.dx
            xp_part = (particles.px[:npart] - self.dpx) * particles.rpp[:npart]
            y_part = particles.y[:npart] - self.dy
            yp_part = (particles.py[:npart] - self.dpy) * particles.rpp[:npart]
            s_part = 0 * x_part
            p_part = particles.energy[:npart] / 1e9 # Energy (not momentum) in GeV

            # Initialise arrays for FORTRAN call
            part_hit = np.zeros(len(x_part), dtype=np.int32)
            part_abs = np.zeros(len(x_part), dtype=np.int32)
            part_impact = np.zeros(len(x_part), dtype=np.float)
            part_indiv = np.zeros(len(x_part), dtype=np.float)
            part_linteract = np.zeros(len(x_part), dtype=np.float)
            nhit_stage = np.zeros(len(x_part), dtype=np.int32)
            nabs_type = np.zeros(len(x_part), dtype=np.int32)
            linside = np.zeros(len(x_part), dtype=np.int32)

            # `linside` is an array of logicals in fortran. Beware of the fortran converion:
            # True <=> -1 (https://stackoverflow.com/questions/39454349/numerical-equivalent-of-true-is-1)

            if self.jaw_F_L != self.jaw_B_L or self.jaw_F_R != self.jaw_B_R:
                raise NotImplementedError
            opening = self.jaw_F_L - self.jaw_F_R
            offset = self.offset + ( self.jaw_F_L + self.jaw_F_R )/2

            matID = pyk2.materials[self.material]['ID']
            
            pyk2.pyk2_run(x_particles=x_part,
                      xp_particles=xp_part,
                      y_particles=y_part,
                      yp_particles=yp_part,
                      s_particles=s_part,
                      p_particles=p_part,              # confusing: this is ENERGY not momentum
                      part_hit=part_hit,
                      part_abs=part_abs,
                      part_impact=part_impact,         # impact parameter
                      part_indiv=part_indiv,           # particle divergence
                      part_linteract=part_linteract,   # interaction length
                      nhit_stage=nhit_stage,
                      nabs_type=nabs_type,
                      linside=linside,
                      matid=matID,
                      is_crystal=False,
                      c_length=self.active_length,
                      c_rotation=self.angle/180.*np.pi,
                      c_aperture=opening,
                      c_offset=offset,
                      c_tilt=self.tilt,
                      c_enom=particles.energy0[0]/1e6, # Reference energy
                      onesided=self.onesided,
                      random_generator_seed=reset_seed,
                      )

            # Masks of hit and survived particles
            mask_lost = part_abs > 0
            mask_hit = part_hit > 0
            mask_not_hit = ~mask_hit
            mask_survived_hit = mask_hit & (~mask_lost)

            state_out = particles.state[:npart].copy()
            state_out[mask_lost] = -333
            particles.state[:npart] = state_out

            # Update particle energy
            ptau_out = particles.ptau[:npart].copy()
            e0 = particles.energy0[:npart]
            beta0 = particles.beta0[:npart]
            ptau_out[mask_survived_hit] = (
                    p_part[mask_survived_hit] * 1e9 - e0[mask_survived_hit]
                ) / (
                    e0[mask_survived_hit] * beta0[mask_survived_hit]
                )
            particles.ptau[:npart] = ptau_out

            # Update transversal coordinates (moving back from collimator frame)
            x_part_out = particles.x[:npart].copy()
            x_part_out[~mask_lost] = x_part[~mask_lost] + self.dx
            particles.x[:npart] = x_part_out

            y_part_out = particles.y[:npart].copy()
            y_part_out[~mask_lost] = y_part[~mask_lost] + self.dy
            particles.y[:npart] = y_part_out

            rpp_out = particles.rpp[:npart]
            px_out = particles.px[:npart]
            px_out[mask_survived_hit] = xp_part[mask_survived_hit]/rpp_out[mask_survived_hit]
            particles.px[:npart] = px_out

            py_out = particles.py[:npart]
            py_out[mask_survived_hit] = yp_part[mask_survived_hit]/rpp_out[mask_survived_hit]
            particles.py[:npart] = py_out

            # Update longitudinal coordinate zeta
            # Note: they have NOT been drifted yet in K2, so we have to do that manually
            rvv_out = particles.rvv[:npart]
            zeta_out = particles.zeta[:npart]
            zeta_out[mask_not_hit] += self.length*(
                                rvv_out[mask_not_hit] - (1 + ( xp_part[mask_not_hit]**2 + yp_part[mask_not_hit]**2)/2 ) 
                            )
            particles.zeta[:npart] = zeta_out

            s_out = particles.s[:npart]
            s_out[mask_not_hit] += self.length
            particles.s[:npart] = s_out

            # Drift inactive back
            L = self.inactive_back
            if L > 0:
                rpp = particles.rpp[:npart]
                xp = particles.px[:npart] * rpp
                yp = particles.py[:npart] * rpp
                dzeta = particles.rvv[:npart] - ( 1 + ( xp*xp + yp*yp ) / 2 )
                particles.x[:npart] += xp * L
                particles.y[:npart] += yp * L
                particles.s[:npart] += L
                particles.zeta[:npart] += dzeta*L

            particles.reorganize()
        
    def to_dict(self):
        thisdict = {}
        thisdict['__class__'] = 'K2Collimator'
        thisdict['n_alloc'] = self._k2engine.n_alloc
        thisdict['random_generator_seed'] = self._k2engine.random_generator_seed
        thisdict['active_length'] = self.active_length
        thisdict['inactive_front'] = self.inactive_front
        thisdict['inactive_back'] = self.inactive_back
        thisdict['angle'] = self.angle
        thisdict['jaw_F_L'] = self.jaw_F_L
        thisdict['jaw_F_R'] = self.jaw_F_R
        thisdict['jaw_B_L'] = self.jaw_B_L
        thisdict['jaw_B_R'] = self.jaw_B_R
        thisdict['onesided'] = 1 if self.onesided else 0
        thisdict['dx'] = self.dx
        thisdict['dy'] = self.dy
        thisdict['dpx'] = self.dpx
        thisdict['dpy'] = self.dpy
        thisdict['offset'] = self.offset
        thisdict['tilt'] = self.tilt
        thisdict['is_active'] = 1 if self.is_active else 0
        thisdict['record_impacts'] = 1 if self.record_impacts else 0
        thisdict['material'] = self.material
        return thisdict


    @classmethod
    def from_dict(cls, thisdict, engine=None):
        if engine is None:
            print("Warning: no engine given! Creating a new one...")
            engine = K2Engine(thisdict['n_alloc'], thisdict['random_generator_seed'])
        else:
            if engine.n_alloc != thisdict['n_alloc']:
                raise ValueError("The provided engine is incompatible with the engine of the "\
                                 "stored element: n_alloc is different.")
            if engine.random_generator_seed != thisdict['random_generator_seed']:
                raise ValueError("The provided engine is incompatible with the engine of the "\
                                 "stored element: random_generator_seed is different.")
        return cls(
            k2engine = engine,
            active_length = thisdict['active_length'],
            inactive_front = thisdict['inactive_front'],
            inactive_back = thisdict['inactive_back'],
            angle = thisdict['angle'],
            jaw_F_L = thisdict['jaw_F_L'],
            jaw_F_R = thisdict['jaw_F_R'],
            jaw_B_L = thisdict['jaw_B_L'],
            jaw_B_R = thisdict['jaw_B_R'],
            onesided = True if thisdict['onesided']==1 else False,
            dx = thisdict['dx'],
            dy = thisdict['dy'],
            dpx = thisdict['dpx'],
            dpy = thisdict['dpy'],
            offset = thisdict['offset'],
            tilt = thisdict['tilt'],
            is_active = True if thisdict['is_active']==1 else False,
            record_impacts = True if thisdict['record_impacts']==1 else False,
            material = thisdict['material']
        )
            
