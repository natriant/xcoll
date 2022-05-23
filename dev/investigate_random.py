import numpy as np
import matplotlib.pyplot as plt

from xcoll.beam_elements.k2.k2_random import get_random_ruth
from xcoll.beam_elements.k2.materials import materials


no_particles = 10000000
vals0 = np.zeros(no_particles)
vals1 = np.zeros(no_particles)

# for i in range(no_particles):
#     vals0[i] = get_random()

cgen=np.array([0.0009982 , 0.00100711, 0.00101619, 0.00102543, 0.00103485,
       0.00104444, 0.00105422, 0.00106419, 0.00107435, 0.00108471,
       0.00109528, 0.00110606, 0.00111706, 0.00112829, 0.00113975,
       0.00115145, 0.0011634 , 0.00117561, 0.00118808, 0.00120083,
       0.00121386, 0.00122718, 0.00124081, 0.00125475, 0.00126902,
       0.00128362, 0.00129857, 0.00131389, 0.00132958, 0.00134566,
       0.00136214, 0.00137905, 0.00139639, 0.00141419, 0.00143246,
       0.00145123, 0.00147051, 0.00149032, 0.00151069, 0.00153165,
       0.00155321, 0.00157541, 0.00159828, 0.00162184, 0.00164613,
       0.00167119, 0.00169704, 0.00172374, 0.00175133, 0.00177985,
       0.00180934, 0.00183987, 0.00187149, 0.00190426, 0.00193825,
       0.00197352, 0.00201015, 0.00204823, 0.00208785, 0.0021291 ,
       0.00217208, 0.00221693, 0.00226375, 0.0023127 , 0.00236391,
       0.00241757, 0.00247384, 0.00253295, 0.00259511, 0.00266057,
       0.00272961, 0.00280256, 0.00287976, 0.00296161, 0.00304856,
       0.00314112, 0.00323989, 0.00334552, 0.00345881, 0.00358065,
       0.0037121 , 0.0038544 , 0.00400904, 0.00417777, 0.00436274,
       0.00456656, 0.00479245, 0.00504446, 0.00532773, 0.00564894,
       0.00601691, 0.00644359, 0.00694566, 0.00754728, 0.008285  ,
       0.00921747, 0.01044656, 0.01217028, 0.0148485 , 0.02      ,
       0.0009982 , 0.00099856, 0.00099892, 0.00099928, 0.00099964,
       0.00100001, 0.00100037, 0.00100073, 0.00100109, 0.00100145,
       0.00100182, 0.00100218, 0.00100254, 0.00100291, 0.00100327,
       0.00100364, 0.001004  , 0.00100437, 0.00100473, 0.0010051 ,
       0.00100546, 0.00100583, 0.00100619, 0.00100656, 0.00100693,
       0.00100729, 0.00100766, 0.00100803, 0.0010084 , 0.00100877,
       0.00100913, 0.0010095 , 0.00100987, 0.00101024, 0.00101061,
       0.00101098, 0.00101135, 0.00101172, 0.00101209, 0.00101246,
       0.00101283, 0.0010132 , 0.00101358, 0.00101395, 0.00101432,
       0.00101469, 0.00101507, 0.00101544, 0.00101581, 0.00101619,
       0.01217028, 0.01225629, 0.01234385, 0.012433  , 0.01252379,
       0.01261626, 0.01271048, 0.01280649, 0.01290437, 0.01300416,
       0.01310593, 0.01320975, 0.0133157 , 0.01342384, 0.01353425,
       0.01364702, 0.01376223, 0.01387998, 0.01400035, 0.01412346,
       0.0142494 , 0.0143783 , 0.01451026, 0.01464543, 0.01478393,
       0.0149259 , 0.01507149, 0.01522088, 0.01537422, 0.01553171,
       0.01569353, 0.0158599 , 0.01603104, 0.0162072 , 0.01638861,
       0.01657558, 0.01676839, 0.01696736, 0.01717285, 0.01738523,
       0.0176049 , 0.01783233, 0.01806799, 0.0183124 , 0.01856617,
       0.01882992, 0.01910435, 0.01939025, 0.01968848, 0.02      ])

for j in range(no_particles):
    vals1[j] = get_random_ruth(cgen)


plt.hist(vals1, bins=200, density=True, log=True)
x = np.linspace(0.001,0.02,500)
cnorm  = 2.607e-5
cnform = 0.8561e3
emr_curr = materials['BE']['emr']
zatom_curr = materials['BE']['zatom']
y = np.e*cnorm*np.exp((-x*cnform)*emr_curr**2) * (zatom_curr/x)**2
plt.plot(x, y)
plt.yscale('log')
plt.show()

