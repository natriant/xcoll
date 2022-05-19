!real(kind=8), save :: zatom_curr ! Current zatom, used for Rutherford scattering integration
!real(kind=8), save :: emr_curr ! Current emr, used for Rutherford scattering integration

subroutine pyk2_init(random_generator_seed)

  use mod_ranlux ,       only : rluxgo, coll_rand  ! for ranlux init
  use coll_common ,      only : rnd_seed !, coll_expandArrays

  implicit none

  integer, intent(in)          :: random_generator_seed

  rnd_seed = random_generator_seed

  ! Initialize random number generator
  if(rnd_seed <  0) rnd_seed = abs(rnd_seed)
  call rluxgo(3, rnd_seed, 0, 0)

end subroutine 


subroutine initialise_random(random_generator_seed, cgen, zatom, emr, hcut)
  use mod_ranlux ,       only : rluxgo     ! for ranlux init
  use mod_funlux ,       only : funlxp
  use coll_k2,           only : zatom_curr, emr_curr, k2coll_ruth

  implicit none

  integer, intent(in)         :: random_generator_seed
  real(kind=8), intent(inout) :: cgen(200)
  real(kind=8), intent(in)    :: zatom
  real(kind=8), intent(in)    :: emr
  real(kind=8), intent(in)    :: hcut
  real(kind=8), parameter     :: tlcut = 0.0009982

  if(random_generator_seed .ge. 0) then
        call rluxgo(3, random_generator_seed, 0, 0)
  end if

  zatom_curr = zatom
  emr_curr = emr
  call funlxp(k2coll_ruth, cgen(1), tlcut, hcut)

end subroutine


subroutine pyk2_crystal( &
  val_part_hit, &
  val_part_abs, &
  val_part_impact, &
  val_part_indiv, &
  run_exenergy, &
  run_anuc, &
  zatom, &
  run_emr, &
  run_rho, &
  run_hcut, &
  run_bnref, &
  run_csref0, &
  run_csref1, &
  run_csref4, &
  run_csref5, &
  run_dlri, & 
  run_dlyi, &
  run_eUm, &
  run_ai, &
  run_collnt, &
  run_bn, &
  c_length, &
  nhit, &
  nabs, &
  lhit, &
  isImp, &
  s, &
  zlm, &
  x, &
  xp, &
  xp_in0, &
  z, &
  zp, &
  p, &
  x_in0)

use coll_k2        ! for scattering
use coll_crystal, only : cry_startElement, cry_interact, cry_calcIonLoss, cry_moveAM, &
                         cry_moveCH, cry_ruth
use parpro
use mathlib_bouncer

implicit none

  integer,         save :: iProc       = 0
  integer,         save :: n_chan      = 0
  integer,         save :: n_VR        = 0
  integer,         save :: n_amorphous = 0

  ! Shared settings for the currently active crystal
  integer,         save :: c_orient   = 0    ! Crystal orientation [0-2]
  real(kind=8),save :: c_rcurv    = zero ! Crystal geometrical parameters [m]
  real(kind=8),save :: c_xmax     = zero ! Crystal geometrical parameters [m]
  real(kind=8),save :: c_ymax     = zero ! Crystal geometrical parameters [m]
  real(kind=8),save :: c_alayer   = zero ! Crystal amorphous layer [mm]
  real(kind=8),save :: c_miscut   = zero ! Crystal miscut angle in rad
  real(kind=8),save :: c_cpTilt   = zero ! Cosine of positive crystal tilt
  real(kind=8),save :: c_spTilt   = zero ! Sine of positive crystal tilt
  real(kind=8),save :: c_cnTilt   = zero ! Cosine of negative crystal tilt
  real(kind=8),save :: c_snTilt   = zero ! Sine of negative crystal tilt
  real(kind=8),save :: c_cBend    = zero ! Cosine of crystal bend
  real(kind=8),save :: c_sBend    = zero ! Sine of crystal bend
  real(kind=8),save :: cry_tilt   = zero ! Crystal tilt angle in rad
  real(kind=8),save :: cry_length = zero ! Crystal length [m]
  real(kind=8),save :: cry_bend   = zero ! Crystal bending angle in rad

  ! Rutherford Scatter
  real(kind=8), parameter     :: tlcut_cry = 0.0009982
  real(kind=8),save :: cgen_cry(200)
  ! integer,         save :: mcurr_cry
  real(kind=8),save :: zatom_curr_cry ! Current zatom, used for Rutherford scattering integration
  real(kind=8),save :: emr_curr_cry ! Current emr, used for Rutherford scattering integration
  

  real(kind=8),save :: enr
  real(kind=8),save :: mom
  real(kind=8),save :: betar
  real(kind=8),save :: gammar
  real(kind=8),save :: bgr
  real(kind=8),save :: tmax
  real(kind=8),save :: plen

  real(kind=8), parameter :: aTF = 0.194e-10 ! Screening function [m]
  real(kind=8), parameter :: dP  = 1.920e-10 ! Distance between planes (110) [m]
  real(kind=8), parameter :: u1  = 0.075e-10 ! Thermal vibrations amplitude

  ! pp cross-sections and parameters for energy dependence
  real(kind=8), parameter :: pptref_cry = 0.040
  real(kind=8), parameter :: freeco_cry = 1.618

  ! Crystal Specific Material Arrays
  ! logical,         save :: validMat(nmat) = .false. ! True for materials the crystal module supports
  ! real(kind=fPrec),save :: dlri     = zero
  ! real(kind=fPrec),save :: dlyi     = zero
  ! real(kind=fPrec),save :: ai       = zero
  ! real(kind=fPrec),save :: eUm      = zero
  ! real(kind=fPrec),save :: collnt   = zero    ! Nuclear Collision length [m]

  ! Processes
  integer, parameter :: proc_out         =  -1     ! Crystal not hit
  integer, parameter :: proc_AM          =   1     ! Amorphous
  integer, parameter :: proc_VR          =   2     ! Volume reflection
  integer, parameter :: proc_CH          =   3     ! Channeling
  integer, parameter :: proc_VC          =   4     ! Volume capture
  integer, parameter :: proc_absorbed    =   5     ! Absorption
  integer, parameter :: proc_DC          =   6     ! Dechanneling
  integer, parameter :: proc_pne         =   7     ! Proton-neutron elastic interaction
  integer, parameter :: proc_ppe         =   8     ! Proton-proton elastic interaction
  integer, parameter :: proc_diff        =   9     ! Single diffractive
  integer, parameter :: proc_ruth        =  10     ! Rutherford scattering
  integer, parameter :: proc_ch_absorbed =  15     ! Channeling followed by absorption
  integer, parameter :: proc_ch_pne      =  17     ! Channeling followed by proton-neutron elastic interaction
  integer, parameter :: proc_ch_ppe      =  18     ! Channeling followed by proton-proton elastic interaction
  integer, parameter :: proc_ch_diff     =  19     ! Channeling followed by single diffractive
  integer, parameter :: proc_ch_ruth     =  20     ! Channeling followed by Rutherford scattering
  integer, parameter :: proc_TRVR        = 100     ! Volume reflection in VR-AM transition region
  integer, parameter :: proc_TRAM        = 101     ! Amorphous in VR-AM transition region

! ================================================================================================ !
!  Initialise the crystal module
! ================================================================================================ !
! subroutine cry_init


! ############################
! ## variables declarations ##
! ############################

integer(kind=4)  , intent(inout) :: val_part_hit
integer(kind=4)  , intent(inout) :: val_part_abs
real(kind=8) , intent(inout) :: val_part_impact
real(kind=8) , intent(inout) :: val_part_indiv

real(kind=8)     , intent(inout) :: run_exenergy
real(kind=8)     , intent(in) :: run_anuc
real(kind=8)     , intent(in) :: zatom
real(kind=8)     , intent(in) :: run_emr
real(kind=8)     , intent(in) :: run_rho
real(kind=8)     , intent(in) :: run_hcut
real(kind=8)     , intent(in) :: run_bnref

real(kind=8)     , intent(in) :: run_csref0
real(kind=8)     , intent(in) :: run_csref1
real(kind=8)     , intent(in) :: run_csref4
real(kind=8)     , intent(in) :: run_csref5

real(kind=8)     , intent(in) :: run_dlri
real(kind=8)     , intent(in) :: run_dlyi
real(kind=8)     , intent(in) :: run_eUm
real(kind=8)     , intent(in) :: run_ai
real(kind=8)     , intent(in) :: run_collnt
real(kind=8)     , intent(inout) :: run_bn
real(kind=8) ,    intent(in) :: c_length

integer,          intent(inout) :: nhit
integer,          intent(inout) :: nabs
integer,          intent(inout) :: lhit
logical(kind=4), intent(inout) :: isImp
real(kind=8),    intent(inout) :: s
real(kind=8),    intent(inout) :: zlm

real(kind=8),    intent(inout) :: x
real(kind=8),    intent(inout) :: xp
real(kind=8),    intent(inout) :: xp_in0
real(kind=8),    intent(inout) :: z
real(kind=8),    intent(inout) :: zp
real(kind=8),    intent(inout) :: p
real(kind=8),    intent(inout) :: x_in0

real(kind=8) s_temp,s_shift,s_rot,s_int
real(kind=8) x_temp,x_shift,x_rot,x_int
real(kind=8) xp_temp,xp_shift,xp_rot,xp_int,xp_tangent
real(kind=8) tilt_int,shift,delta,a_eq,b_eq,c_eq
real(kind=8) s_P, x_P, s_P_tmp, x_P_tmp, s_imp

! needs to be passed from cry_startElement
integer cry_proc, cry_proc_prev, cry_proc_tmp
cry_proc = -1
cry_proc_prev = -1
cry_proc_tmp = -1


  s_temp     = zero
  s_shift    = zero
  s_rot      = zero
  s_int      = zero
  x_temp     = zero
  x_shift    = zero
  x_rot      = zero
  x_int      = zero
  xp_temp    = zero
  xp_shift   = zero
  xp_rot     = zero
  xp_int     = zero
  xp_tangent = zero
  tilt_int   = zero
  shift      = zero
  delta      = zero
  a_eq       = zero
  b_eq       = zero
  c_eq       = zero
  s_imp      = zero

  ! Determining if particle previously interacted with a crystal and storing the process ID
  if(cry_proc_tmp /= proc_out) then
    cry_proc_prev = cry_proc_tmp
  end if

  iProc       = proc_out
  cry_proc    = proc_out

  ! Transform in the crystal reference system
  ! 1st transformation: shift of the center of the reference frame
  if(cry_tilt < zero) then
    s_shift = s
    shift   = c_rcurv*(1 - c_cpTilt)
    if(cry_tilt < -cry_bend) then
      shift = c_rcurv*(c_cnTilt - cos_mb(cry_bend - cry_tilt))
    end if
    x_shift = x - shift
  else
    s_shift = s
    x_shift = x
  end if

  ! 2nd transformation: rotation
  s_rot  = x_shift*c_spTilt + s_shift*c_cpTilt
  x_rot  = x_shift*c_cpTilt - s_shift*c_spTilt
  xp_rot = xp - cry_tilt

  ! 3rd transformation: drift to the new coordinate s=0
  xp = xp_rot
  x  = x_rot - xp_rot*s_rot
  z  = z - zp*s_rot
  s  = zero

! Check that particle hit the crystal
  if(x >= zero .and. x < c_xmax) then

    ! MISCUT first step: P coordinates (center of curvature of crystalline planes)
    s_P = (c_rcurv-c_xmax)*sin_mb(-c_miscut)
    x_P = c_xmax + (c_rcurv-c_xmax)*cos_mb(-c_miscut)

    call cry_interact(x,xp,z,zp,p,cry_length,s_P,x_P,run_exenergy,run_anuc,zatom,run_emr,run_rho,run_hcut,&
                      run_bnref,run_csref0,run_csref1,run_csref4,run_csref5,run_dlri,run_dlyi,run_eUm,run_ai,run_collnt,run_bn)
    s   = c_rcurv*c_sBend
    zlm = c_rcurv*c_sBend
    if(iProc /= proc_out) then
      isImp        = .true.
      nhit         = nhit + 1
      lhit         = 1
      val_part_impact = x_in0
      val_part_indiv = xp_in0
    end if

  else

    if(x < zero) then ! Crystal can be hit from below
      xp_tangent = sqrt((-(2*x)*c_rcurv + x**2)/(c_rcurv**2))
    else              ! Crystal can be hit from above
      xp_tangent = asin_mb((c_rcurv*(1 - c_cBend) - x)/sqrt(((2*c_rcurv)*(c_rcurv - x))*(1 - c_cBend) + x**2))
    end if

    ! If the hit is below, the angle must be greater or equal than the tangent,
    ! or if the hit is above, the angle must be smaller or equal than the tangent
    if((x < zero .and. xp >= xp_tangent) .or. (x >= zero .and. xp <= xp_tangent)) then

! If it hits the crystal, calculate in which point and apply the transformation and drift to that point
      a_eq  = 1 + xp**2
      b_eq  = (2*xp)*(x - c_rcurv)
      c_eq  = -(2*x)*c_rcurv + x**2
      delta = b_eq**2 - 4*(a_eq*c_eq)
      s_int = (-b_eq - sqrt(delta))/(2*a_eq)
      s_imp = s_int

      ! MISCUT first step: P coordinates (center of curvature of crystalline planes)
      s_P_tmp = (c_rcurv-c_xmax)*sin_mb(-c_miscut)
      x_P_tmp = c_xmax + (c_rcurv-c_xmax)*cos_mb(-c_miscut)

      if(s_int < c_rcurv*c_sBend) then
        ! Transform to a new reference system: shift and rotate
        x_int  = xp*s_int + x
        xp_int = xp
        z      = z + zp*s_int
        x      = zero
        s      = zero

        tilt_int = s_int/c_rcurv
        xp       = xp-tilt_int

        ! MISCUT first step (bis): transform P in new reference system
        ! Translation
        s_P_tmp = s_P_tmp - s_int
        x_P_tmp = x_P_tmp - x_int
        ! Rotation
        s_P = s_P_tmp*cos_mb(tilt_int) + x_P_tmp*sin_mb(tilt_int)
        x_P = -s_P_tmp*sin_mb(tilt_int) + x_P_tmp*cos_mb(tilt_int)

        call cry_interact(x,xp,z,zp,p,cry_length-(tilt_int*c_rcurv),s_P,x_P,run_exenergy,run_anuc,&
                          zatom,run_emr,run_rho,run_hcut,run_bnref,run_csref0,run_csref1,run_csref4,run_csref5,&
                          run_dlri,run_dlyi,run_eUm,run_ai,run_collnt,run_bn)
        s   = c_rcurv*sin_mb(cry_bend - tilt_int)
        zlm = c_rcurv*sin_mb(cry_bend - tilt_int)
        if(iProc /= proc_out) then
          x_rot    = x_int
          s_rot    = s_int
          xp_rot   = xp_int
          s_shift  =  s_rot*c_cnTilt + x_rot*c_snTilt
          x_shift  = -s_rot*c_snTilt + x_rot*c_cnTilt
          xp_shift = xp_rot + cry_tilt

          if(cry_tilt < zero) then
            x_in0  = x_shift + shift
            xp_in0 = xp_shift
          else
            x_in0  = x_shift
            xp_in0 = xp_shift
          end if

          isImp           = .true.
          nhit            = nhit + 1
          lhit            = 1
          val_part_impact = x_in0
          val_part_indiv  = xp_in0
        end if

        ! un-rotate
        x_temp  = x
        s_temp  = s
        xp_temp = xp
        s       =  s_temp*cos_mb(-tilt_int) + x_temp*sin_mb(-tilt_int)
        x       = -s_temp*sin_mb(-tilt_int) + x_temp*cos_mb(-tilt_int)
        xp      = xp_temp + tilt_int

        ! 2nd: shift back the 2 axis
        x = x + x_int
        s = s + s_int

      else

        s = c_rcurv*sin_mb(cry_length/c_rcurv)
        x = x + s*xp
        z = z + s*zp

      end if

    else

      s = c_rcurv*sin_mb(cry_length/c_rcurv)
      x = x + s*xp
      z = z + s*zp

    end if

  end if

  ! transform back from the crystal to the collimator reference system
  ! 1st: un-rotate the coordinates
  x_rot  = x
  s_rot  = s
  xp_rot = xp

  s_shift  =  s_rot*c_cnTilt + x_rot*c_snTilt
  x_shift  = -s_rot*c_snTilt + x_rot*c_cnTilt
  xp_shift = xp_rot + cry_tilt

  ! 2nd: shift back the reference frame
  if(cry_tilt < zero) then
    s  = s_shift
    x  = x_shift + shift
    xp = xp_shift
  else
    x  = x_shift
    s  = s_shift
    xp = xp_shift
  end if

  ! 3rd: shift to new S=Length position
  x = xp*(c_length - s) + x
  z = zp*(c_length - s) + z
  s = c_length

  nabs = 0
  cry_proc = iProc
  if(iProc == proc_AM) then
    n_amorphous = n_amorphous + 1
  else if(iProc == proc_VR) then
    n_VR = n_VR + 1
  else if(iProc == proc_CH) then
    n_chan = n_Chan + 1
  else if(iProc == proc_absorbed) then
    nabs = 1   ! TODO: do we need to set part_abs_pos etc?
  else if(iProc == proc_ch_absorbed) then
    nabs = 1
  end if

  ! Storing the process ID for the next interaction
  cry_proc_tmp = cry_proc

end subroutine



subroutine pyk2_jaw( &
  run_exenergy, &
  run_anuc, &
  run_zatom, &
  run_rho, &
  run_radl, &
  run_cprob, &
  run_xintl, &
  run_bn, &
  run_ecmsq, &
  run_xln15s, &
  run_bpp, &
  run_cgen, &
  p0, &
  nabs, &
  s, &
  zlm, &
  x, &
  xp, &
  z, &
  zp, &
  dpop)

! for scattering
use coll_k2, only :  k2coll_ruth
                      
use mod_ranlux, only : coll_rand
use coll_common
use mathlib_bouncer                       

implicit none

! ############################
! ## variables declarations ##
! ############################

real(kind=8)     , intent(inout) :: run_exenergy
real(kind=8)     , intent(in) :: run_anuc
real(kind=8)     , intent(in) :: run_zatom
real(kind=8)     , intent(in) :: run_rho
real(kind=8)     , intent(in) :: run_radl
real(kind=8)     , intent(in) :: run_cprob(0:5)
real(kind=8)     , intent(in) :: run_xintl
real(kind=8)     , intent(inout) :: run_bn
real(kind=8)     , intent(in) :: run_ecmsq
real(kind=8)     , intent(in) :: run_xln15s
real(kind=8)     , intent(in) :: run_bpp
real(kind=8)     , intent(in) :: run_cgen(200)
real(kind=8),  intent(inout) :: p0
integer,          intent(inout) :: nabs
real(kind=8),    intent(inout) :: s
real(kind=8),    intent(inout) :: zlm
real(kind=8),    intent(inout) :: x
real(kind=8),    intent(inout) :: xp
real(kind=8),    intent(inout) :: z
real(kind=8),    intent(inout) :: zp
real(kind=8),    intent(inout) :: dpop

real(kind=8) pyk2_gettran 
integer pyk2_ichoix

real(kind=8) xInt,xpInt,yInt,ypInt,sInt
real(kind=8) m_dpodx,p,rlen,t,dxp,dzp,p1,zpBef,xpBef,pBef,run_zlm1,xpsd,zpsd,psd
integer inter,nabs_tmp


end subroutine


! subroutine pyk2_calcIonLoss(p,rlen,il_exenergy,il_anuc,il_zatom,il_rho,EnLo)

!   use mathlib_bouncer

!   implicit none

!   real(kind=8), intent(in)  :: p           ! p momentum in GeV
!   real(kind=8), intent(in)  :: rlen           ! rlen length traversed in material (meters)
!   real(kind=8), intent(inout)  :: il_exenergy  ! il_exenergy
!   real(kind=8), intent(in)  :: il_anuc      ! il_anuc 
!   real(kind=8), intent(in)  :: il_zatom     ! il_zatom
!   real(kind=8), intent(in)  :: il_rho       ! il_rho
!   real(kind=8), intent(inout) :: EnLo         ! EnLo energy loss in GeV/meter

!   !call k2coll_calcIonLoss(p,rlen,il_exenergy,il_anuc,il_zatom,il_rho,EnLo)

!   real(kind=8) exEn,thl,Tt,cs_tail,prob_tail,enr,mom,betar,gammar,bgr,kine,Tmax,plen
!   real(kind=8), parameter :: k = 0.307075 ! Constant in front of Bethe-Bloch [MeV g^-1 cm^2]
!   real(kind=8) pyk2_rand

!   mom    = p*1.0e3                     ! [GeV/c] -> [MeV/c]
!   enr    = (mom*mom + 938.271998*938.271998)**0.5 ! [MeV]
!   gammar = enr/938.271998
!   betar  = mom/enr
!   bgr    = betar*gammar
!   kine   = ((2*0.510998902)*bgr)*bgr

!   ! Mean excitation energy
!   exEn = il_exenergy*1.0e3 ! [MeV]

!   ! Tmax is max energy loss from kinematics
!   Tmax = kine/(1 + (2*gammar)*(0.510998902/938.271998) + (0.510998902/938.271998)**2) ! [MeV]

!   ! Plasma energy - see PDG 2010 table 27.1
!   plen = (((il_rho*il_zatom)/il_anuc)**0.5)*28.816e-6 ! [MeV]

!   ! Calculate threshold energy
!   ! Above this threshold, the cross section for high energy loss is calculated and then
!   ! a random number is generated to determine if tail energy loss should be applied, or only mean from Bethe-Bloch
!   ! below threshold, only the standard Bethe-Bloch is used (all particles get average energy loss)

!   ! thl is 2*width of Landau distribution (as in fig 27.7 in PDG 2010). See Alfredo's presentation for derivation
!   thl = ((((4*(k*il_zatom))*rlen)*1.0e2)*il_rho)/(il_anuc*betar**2) ! [MeV]

!   ! Bethe-Bloch mean energy loss
!   EnLo = ((k*il_zatom)/(il_anuc*betar**2)) * ( &
!     0.5*log_mb((kine*Tmax)/(exEn*exEn)) - betar**2 - log_mb(plen/exEn) - log_mb(bgr) + 0.5 &
!   )
!   EnLo = ((EnLo*il_rho)*1.0e-1)*rlen ! [GeV]

!   ! Threshold Tt is Bethe-Bloch + 2*width of Landau distribution
!   Tt = EnLo*1.0e3 + thl ! [MeV]

!   ! Cross section - see Alfredo's presentation for derivation
!   cs_tail = ((k*il_zatom)/(il_anuc*betar**2)) * ( &
!     0.5*((1/Tt)-(1/Tmax)) - (log_mb(Tmax/Tt)*betar**2)/(2*Tmax) + (Tmax-Tt)/((4*gammar**2)*938.271998**2) &
!   )

!   ! Probability of being in tail: cross section * density * path length
!   prob_tail = ((cs_tail*il_rho)*rlen)*1.0e2

!   ! Determine based on random number if tail energy loss occurs.
!   if(pyk2_rand() < prob_tail) then
!     EnLo = ((k*il_zatom)/(il_anuc*betar**2)) * ( &
!       0.5*log_mb((kine*Tmax)/(exEn*exEn)) - betar**2 - log_mb(plen/exEn) - log_mb(bgr) + &
!       0.5 + TMax**2/((8*gammar**2)*938.271998**2) &
!     )
!     EnLo = (EnLo*il_rho)*1.0e-1 ! [GeV/m]
!   else
!     ! If tail energy loss does not occur, just use the standard Bethe-Bloch
!     EnLo = EnLo/rlen  ! [GeV/m]
!   end if

! end subroutine


! real(kind=8) function pyk2_gettran(inter,p,tt_bn,tt_cgen,tt_ecmsq,tt_xln15s,tt_bpp)

!   use mathlib_bouncer
!   use mod_funlux, only: funlux

!   implicit none

!   integer,       intent(in)    :: inter
!   real(kind=8), intent(inout) :: p
!   real(kind=8), intent(in)    :: tt_bn
!   real(kind=8), intent(in)    :: tt_cgen(200)
!   real(kind=8), intent(in)    :: tt_xln15s
!   real(kind=8), intent(in)    :: tt_ecmsq
!   real(kind=8), intent(in)    :: tt_bpp

!   real(kind=8) xm2,bsd,xran(1)
!   real(kind=8) pyk2_rand

!   ! Neither if-statements below have an else, so defaulting function return to zero.
!   pyk2_gettran = 0

!   select case(inter)
!   case(2) ! Nuclear Elastic
!     pyk2_gettran = (-1*log_mb(pyk2_rand()))/tt_bn
!   case(3) ! pp Elastic
!     pyk2_gettran = (-1*log_mb(pyk2_rand()))/tt_bpp
!   case(4) ! Single Diffractive
!     xm2 = exp_mb(pyk2_rand() * tt_xln15s)
!     p   = p * (1 - xm2/tt_ecmsq)
!     if(xm2 < 2) then
!       bsd = 2 * tt_bpp
!     else if(xm2 >= 2 .and. xm2 <= 5) then
!       bsd = ((106.0 - 17.0*xm2)*tt_bpp)/36.0
!     else
!       bsd = (7*tt_bpp)/12.0
!     end if
!     pyk2_gettran = (-1*log_mb(pyk2_rand()))/bsd
!   case(5) ! Coulomb
!     call funlux(tt_cgen(1), xran, 1)
!     pyk2_gettran = xran(1)
!   end select


! end function pyk2_gettran


! subroutine pyk2_soln3(a, b, dh, smax, s)

!   real(kind=8), intent(in)    :: a
!   real(kind=8), intent(in)    :: b
!   real(kind=8), intent(in)    :: dh
!   real(kind=8), intent(in)    :: smax
!   real(kind=8), intent(inout) :: s

!   real(kind=8) c

!   if(b == 0) then
!     s = a**0.6666666666666667
!   ! s = a**(two/three)
!     if(s > smax) s = smax
!     return
!   end if

!   if(a == 0) then
!     if(b > 0) then
!       s = b**2
!     else
!       s = 0
!     end if
!     if(s > smax) s=smax
!     return
!   end if

!   if(b > 0) then
!     if(smax**3 <= (a + b*smax)**2) then
!       s = smax
!       return
!     else
!       s = smax*0.5
!       call pyk2_iterat(a,b,dh,s)
!     end if
!   else
!     c = (-1*a)/b
!     if(smax < c) then
!       if(smax**3 <= (a + b*smax)**2) then
!         s = smax
!         return
!       else
!         s = smax*0.5
!         call pyk2_iterat(a,b,dh,s)
!       end if
!     else
!       s = c*0.5
!       call pyk2_iterat(a,b,dh,s)
!     end if
!   end if

! end subroutine pyk2_soln3


! subroutine pyk2_iterat(a, b, dh, s)

!   real(kind=8), intent(in)    :: a
!   real(kind=8), intent(in)    :: b
!   real(kind=8), intent(in)    :: dh
!   real(kind=8), intent(inout) :: s

!   real(kind=8) ds

!   ds = s

! 10 continue
!   ds = ds*0.5

!   if(s**3 < (a+b*s)**2) then
!     s = s+ds
!   else
!     s = s-ds
!   end if

!   if(ds < dh) then
!     return
!   else
!     goto 10
!   end if

! end subroutine pyk2_iterat


! subroutine pyk2_mcs(s, mc_radl, mc_zlm1, mc_p0, mc_x, mc_xp, mc_z, mc_zp, mc_dpop)

!   real(kind=8), intent(inout) :: s
!   real(kind=8), intent(in)    :: mc_radl
!   real(kind=8), intent(in)    :: mc_zlm1
!   real(kind=8), intent(in)    :: mc_p0

!   real(kind=8), intent(inout) :: mc_x
!   real(kind=8), intent(inout) :: mc_xp
!   real(kind=8), intent(inout) :: mc_z
!   real(kind=8), intent(inout) :: mc_zp
!   real(kind=8), intent(inout) :: mc_dpop

!   real(kind=8) theta,rlen0,rlen,ae,be,rad_len

!   real(kind=8), parameter :: h   = 0.001
!   real(kind=8), parameter :: dh  = 0.0001
!   real(kind=8), parameter :: bn0 = 0.4330127019

!   ! radl_mat = mc_radl
!   theta    = 13.6e-3/(mc_p0*(1+mc_dpop)) ! dpop   = (p - p0)/p0
!   rad_len  = mc_radl


!   mc_x     = (mc_x/theta)/mc_radl
!   mc_xp    = mc_xp/theta
!   mc_z     = (mc_z/theta)/mc_radl
!   mc_zp    = mc_zp/theta
!   rlen0 = mc_zlm1/mc_radl
!   rlen  = rlen0

! 10 continue
!   ae = bn0*mc_x
!   be = bn0*mc_xp

!     call pyk2_soln3(ae,be,dh,rlen,s)
!     if(s < h) s = h
!     call pyk2_scamcs(mc_x,mc_xp,s)
!     if(mc_x <= 0) then
!     s = (rlen0-rlen)+s
!     goto 20
!   end if
!   if(s+dh >= rlen) then
!     s = rlen0
!     goto 20
!   end if
!   rlen = rlen-s
!   goto 10

! 20 continue
!     call pyk2_scamcs(mc_z,mc_zp,s)
!     s  = s*mc_radl
!   mc_x  = (mc_x*theta)*mc_radl
!   mc_xp = mc_xp*theta
!   mc_z  = (mc_z*theta)*mc_radl
!   mc_zp = mc_zp*theta

! end subroutine pyk2_mcs



! subroutine pyk2_tetat(t,p,tx,tz)

!   implicit none

!   real(kind=8), intent(in)  :: t
!   real(kind=8), intent(in)  :: p
!   real(kind=8), intent(inout) :: tx
!   real(kind=8), intent(inout) :: tz

!   !call k2coll_tetat(t,p,tx,tz)

!   real(kind=8) va,vb,va2,vb2,r2,teta
!   real(kind=8) pyk2_rand

!   teta = sqrt(t)/p
! 10 continue
!   va  = 2*pyk2_rand() - 1
!   vb  = pyk2_rand()
!   va2 = va**2
!   vb2 = vb**2
!   r2  = va2 + vb2
!   if(r2 > 1) goto 10
!   tx  = (teta*((2*va)*vb))/r2
!   tz  = (teta*(va2 - vb2))/r2

! end subroutine


! integer function pyk2_ichoix(ich_cprob)

!   implicit none

!   real(kind=8), intent(in) :: ich_cprob(0:5)      ! Cprob to choose an interaction in iChoix
!   real(kind=8) pyk2_rand

!   integer i
!   real(kind=8) aran

!   aran = pyk2_rand()
!   i    = 1
! 10 continue
!   if(aran > ich_cprob(i)) then
!     i = i+1
!     goto 10
!   end if

!   pyk2_ichoix = i

! end function pyk2_ichoix


real(kind=8) function pyk2_rand() 

  use mod_ranlux, only: coll_rand

  implicit none

  pyk2_rand = coll_rand()

end function pyk2_rand


subroutine pyk2_funlux(array,xran,len) 

  use mod_funlux, only: funlux

  implicit none

  real(kind=8), intent(in)  :: array(200)
  integer, intent(in)       :: len
  real(kind=8), intent(inout) :: xran(len)

  call funlux(array,xran,len)

end subroutine pyk2_funlux


! real(kind=8) function pyk2_ruth(t)

!   use mathlib_bouncer
!   !use coll_materials
!   use coll_k2,           only : zatom_curr, emr_curr

!   real(kind=8), intent(in) :: t
!   !real(kind=8), intent(in) :: ru_emr

!   ! DM: changed 2.607d-4 to 2.607d-5 to fix Rutherford bug
!   real(kind=8), parameter :: cnorm  = 2.607e-5
!   real(kind=8), parameter :: cnform = 0.8561e3

!   pyk2_ruth = (cnorm*exp_mb(((-1*t)*cnform)*emr_curr**2)) * (zatom_curr/t)**2

! end function pyk2_ruth