from letters import Letter, TextLine

import numpy as np
cimport numpy as np

cimport cython

# Initial a C class for internal use
cdef class CLetter:
    cdef np.ndarray label_map, stats, centroid
    cdef int label, x, y, w, h, r, b

    def __init__(self, letter):
        self.label = letter.label
        self.label_map = letter.label_map
        self.stats = letter.stats
        self.centroid = letter.centroid
        self.x = letter.x
        self.y = letter.y
        self.w = letter.w
        self.h = letter.h
        self.r = self.x + self.w
        self.b = self.y + self.h

    # Convert an internal C class back to Python class object
    def letter(self):
        return Letter(self.label, self.label_map, self.stats, self.centroid)

def collate_lines(int AH, list letters):
    cdef int score, best_score, line_len
    cdef CLetter last1, last2, cl, letter, first, last
    cdef list lines, best_candidate

    # Convert Python object into C object
    letters = [CLetter(l) for l in letters]
    # Sort from left to right
    letters.sort(key=lambda CLetter cl: cl.x)

    lines = []
    # Idea: for each letter, find a best line for it
    #       if we cannot find a suitable line for it, create a line start from this letter
    for letter in letters:
        best_candidate = []
        best_score = 100000
        for line in lines:
            line_len = len(line)
            last1 = line[-1]
            last2 = line[-2] if line_len > 1 else last1
            score = best_score
            # if this letter is not too far from last1 in terms of x coordinate
            # and last1 should be on top of letter.b+3
            # and letter should be on top of last
            # (Intuition, letter and last's ys should not be too far away)
            if letter.x < last1.r + 4 * AH \
                    and last1.y <= letter.b + 3 and letter.y <= last1.b + 3:
                # Use Mahattan distance
                score = letter.x - last1.r + abs(letter.y - last1.y)
            # if a letter does not pass the condition above, we give it a second chance
            # if this letter's x coordinates is not too far from last2
            # and letter is on top of last2 and last2 is on top of letter
            elif line_len > 1 \
                    and letter.x < last2.x + last2.w + AH \
                    and last2.y <= letter.b and letter.y <= last2.b:
                score = letter.x - last2.r + abs(letter.y - last2.y)
            if score < best_score - 0.1:
                best_score = score
                best_candidate = line

        if best_candidate:
            first = best_candidate[0]
            last = best_candidate[-1]
            # if there exists a suitable line for this letter, append this letter behind this line
            best_candidate.append(letter)
            if letter.x - last.x > 300 or letter.x < first.x or letter.x - first.x > 2000:
                print "agggghhh"
                print "first", first.letter()
                print "last ", last.letter()
                print "new  ", letter.letter()
            # print "  selected:", x, y, w, h
        else:
            # otherwise, create a new line starting from this letter
            lines.append([letter])

    return [TextLine([cl.letter() for cl in line]) for line in lines]
