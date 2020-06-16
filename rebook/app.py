import numpy as np
import dewarp
import argparse
from pathlib import Path
import lib
import cv2

class Dewarper():
    def __init__(self, gcs_poly_degree, line_poly_degree, debug_folder=Path("./dewarp"), verbose=True):
        if verbose:
            print("[!] Dewarper currently does not support parallelism due to the modification of global variables in dewarp.py.")
        assert isinstance(gcs_poly_degree, int) and gcs_poly_degree > 0
        assert isinstance(line_poly_degree, int) and line_poly_degree > 0

        self.gcs_poly_degree = gcs_poly_degree
        self.line_poly_degree = line_poly_degree
        dewarp.set_global_params(gcs_poly_degree, line_poly_degree)
        if verbose:
            print("[*] GCS surface polynomial degree: {} and Text line polynomial degree: {}"\
                    .format(gcs_poly_degree, line_poly_degree))

        lib.debug = True
        lib.debug_prefix = [str(debug_folder)]
        np.set_printoptions(linewidth=130, precision=4)

    def dewarp(self, img, output_width=None, n_tries=30) -> np.ndarray:
        '''
            Args:
                img (np.ndarray): an BGR np.array

            Returns:
                dewarped_img (np.ndarray): an BGR dewarped np.array
        '''
        assert isinstance(img, np.ndarray) and len(img.shape) == 3
        assert output_width is None or isinstance(output_width, int)
        assert isinstance(n_tries, int) and n_tries > 0

        # Default output_width is the same as the original height of the img
        if output_width is None:
            output_width = img.shape[1]

        dewarped_img = dewarp.kim2014(img, n_points_w=output_width, n_tries=n_tries)[0]

        assert isinstance(dewarped_img, np.ndarray)
        assert dewarped_img.shape[1] == output_width
        return dewarped_img

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("img_path", type=Path)
    parser.add_argument("out_path", type=Path)
    parser.add_argument("gcs_poly_deg", type=int)
    parser.add_argument("line_poly_deg", type=int)
    parser.add_argument("--n_tries", type=int, default=30)
    args = parser.parse_args()

    img = cv2.imread(str(args.img_path))
    dewarper = Dewarper(gcs_poly_degree=args.gcs_poly_deg, line_poly_degree=args.line_poly_deg, verbose=True)
    dewarped_img = dewarper.dewarp(img, n_tries=args.n_tries)
    cv2.imwrite(str(args.out_path), dewarped_img)
