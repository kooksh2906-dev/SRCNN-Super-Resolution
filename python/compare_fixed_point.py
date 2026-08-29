import numpy as np

reference_q = np.load('dump_int16/output_fp32.npy')
integer_q = np.load('golden_int16/output_q.npy')

difference_lsb = (
    integer_q.astype(np.int64) -
    reference_q.astype(np.int64)
)

difference_real = difference_lsb.astype(np.float64) / (1 << 15)

max_error = np.max(np.abs(difference_real))
mean_error = np.mean(np.abs(difference_real))
rmse = np.sqrt(np.mean(difference_real ** 2))
mse = np.mean(difference_real ** 2)

if mse == 0:
    psnr = float('inf')
else:
    # 출력 범위가 0~1이므로 peak=1
    psnr = 10 * np.log10(1.0 / mse)

print('Maximum error :', max_error)
print('Mean error    :', mean_error)
print('RMSE          :', rmse)
print('INT16 vs FP32 PSNR:', psnr, 'dB')