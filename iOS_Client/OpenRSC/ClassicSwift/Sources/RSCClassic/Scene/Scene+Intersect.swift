// Port of scene_intersect (generated 1:1 from scene.c; do not hand-tidy).
extension Scene {
    static func intersect(_ vertex_view_x_a: [Int32], _ vertex_view_y_a: [Int32], _ vertex_view_x_b: [Int32],
                          _ vertex_view_y_b: [Int32], _ length_a: Int, _ length_b: Int) -> Bool {

    var byte0 = 0
    var view_y_a = vertex_view_y_a[0]
    var k20 = view_y_a
    var k = 0
    var view_y_b = vertex_view_y_b[0]
    var l20 = view_y_b
    var i1 = 0

    for i in 1..<length_a {
        if (vertex_view_y_a[i] < view_y_a) {
            view_y_a = vertex_view_y_a[i]
            k = i
        } else if (vertex_view_y_a[i] > k20) {
            k20 = vertex_view_y_a[i]
        }
    }

    for i in 1..<length_b {
        if (vertex_view_y_b[i] < view_y_b) {
            view_y_b = vertex_view_y_b[i]
            i1 = i
        } else if (vertex_view_y_b[i] > l20) {
            l20 = vertex_view_y_b[i]
        }
    }

    if ((view_y_b >= k20)) {
        return false
    }

    if ((view_y_a >= l20)) {
        return false
    }

    var l = 0
    var j1 = 0
    var flag = false

    if (vertex_view_y_a[k] < vertex_view_y_b[i1]) {
        l = k
        while vertex_view_y_a[l] < vertex_view_y_b[i1] { l = (l + 1) % length_a }

        while vertex_view_y_a[k] < vertex_view_y_b[i1] { k = (k - 1 + length_a) % length_a }

        let k1 = m306(vertex_view_x_a[(k + 1) % length_a],
                                 vertex_view_y_a[(k + 1) % length_a],
                                 vertex_view_x_a[k], vertex_view_y_a[k],
                                 vertex_view_y_b[i1])

        let k6 = m306(vertex_view_x_a[(l - 1 + length_a) % length_a],
                                 vertex_view_y_a[(l - 1 + length_a) % length_a],
                                 vertex_view_x_a[l], vertex_view_y_a[l],
                                 vertex_view_y_b[i1])

        let l10 = vertex_view_x_b[i1]
        flag = (k1 < l10) || (k6 < l10)

        if (m308(k1, k6, l10, flag)) {
            return true
        }

        j1 = (i1 + 1) % length_b
        i1 = (i1 - 1 + length_b) % length_b

        if (k == l) {
            byte0 = 1
        }
    } else {
        j1 = i1
        while vertex_view_y_b[j1] < vertex_view_y_a[k] { j1 = (j1 + 1) % length_b }

        while vertex_view_y_b[i1] < vertex_view_y_a[k] { i1 = (i1 - 1 + length_b) % length_b }

        let l1 = vertex_view_x_a[k]

        let i11 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                  vertex_view_y_b[(i1 + 1) % length_b],
                                  vertex_view_x_b[i1], vertex_view_y_b[i1],
                                  vertex_view_y_a[k])

        let l15 = m306(
            vertex_view_x_b[(j1 - 1 + length_b) % length_b],
            vertex_view_y_b[(j1 - 1 + length_b) % length_b],
            vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_a[k])

        flag = (l1 < i11) || (l1 < l15)

        if (m308(i11, l15, l1, !flag)) {
            return true
        }

        l = (k + 1) % length_a
        k = (k - 1 + length_a) % length_a

        if (i1 == j1) {
            byte0 = 2
        }
    }

    while (byte0 == 0) {
        if (vertex_view_y_a[k] < vertex_view_y_a[l]) {
            if (vertex_view_y_a[k] < vertex_view_y_b[i1]) {
                if (vertex_view_y_a[k] < vertex_view_y_b[j1]) {
                    let i2 = vertex_view_x_a[k]

                    let l6 = m306(
                        vertex_view_x_a[(l - 1 + length_a) % length_a],
                        vertex_view_y_a[(l - 1 + length_a) % length_a],
                        vertex_view_x_a[l], vertex_view_y_a[l],
                        vertex_view_y_a[k])

                    let j11 = m306(
                        vertex_view_x_b[(i1 + 1) % length_b],
                        vertex_view_y_b[(i1 + 1) % length_b],
                        vertex_view_x_b[i1], vertex_view_y_b[i1],
                        vertex_view_y_a[k])

                    let i16 = m306(
                        vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                        vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                        vertex_view_x_b[j1], vertex_view_y_b[j1],
                        vertex_view_y_a[k])

                    if (m307(i2, l6, j11, i16, flag)) {
                        return true
                    }

                    k = (k - 1 + length_a) % length_a

                    if (k == l) {
                        byte0 = 1
                    }
                } else {
                    let j2 = m306(
                        vertex_view_x_a[(k + 1) % length_a],
                        vertex_view_y_a[(k + 1) % length_a], vertex_view_x_a[k],
                        vertex_view_y_a[k], vertex_view_y_b[j1])

                    let i7 = m306(
                        vertex_view_x_a[(l - 1 + length_a) % length_a],
                        vertex_view_y_a[(l - 1 + length_a) % length_a],
                        vertex_view_x_a[l], vertex_view_y_a[l],
                        vertex_view_y_b[j1])

                    let k11 = m306(
                        vertex_view_x_b[(i1 + 1) % length_b],
                        vertex_view_y_b[(i1 + 1) % length_b],
                        vertex_view_x_b[i1], vertex_view_y_b[i1],
                        vertex_view_y_b[j1])

                    let j16 = vertex_view_x_b[j1]

                    if (m307(j2, i7, k11, j16, flag)) {
                        return true
                    }

                    j1 = (j1 + 1) % length_b

                    if (i1 == j1) {
                        byte0 = 2
                    }
                }
            } else if (vertex_view_y_b[i1] < vertex_view_y_b[j1]) {
                let k2 = m306(vertex_view_x_a[(k + 1) % length_a],
                                         vertex_view_y_a[(k + 1) % length_a],
                                         vertex_view_x_a[k], vertex_view_y_a[k],
                                         vertex_view_y_b[i1])

                let j7 = m306(
                    vertex_view_x_a[(l - 1 + length_a) % length_a],
                    vertex_view_y_a[(l - 1 + length_a) % length_a],
                    vertex_view_x_a[l], vertex_view_y_a[l],
                    vertex_view_y_b[i1])

                let l11 = vertex_view_x_b[i1]

                let k16 = m306(
                    vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_x_b[j1], vertex_view_y_b[j1],
                    vertex_view_y_b[i1])

                if (m307(k2, j7, l11, k16, flag)) {
                    return true
                }

                i1 = (i1 - 1 + length_b) % length_b

                if (i1 == j1) {
                    byte0 = 2
                }
            } else {
                let l2 = m306(vertex_view_x_a[(k + 1) % length_a],
                                         vertex_view_y_a[(k + 1) % length_a],
                                         vertex_view_x_a[k], vertex_view_y_a[k],
                                         vertex_view_y_b[j1])

                let k7 = m306(
                    vertex_view_x_a[(l - 1 + length_a) % length_a],
                    vertex_view_y_a[(l - 1 + length_a) % length_a],
                    vertex_view_x_a[l], vertex_view_y_a[l],
                    vertex_view_y_b[j1])

                let i12 = m306(
                    vertex_view_x_b[(i1 + 1) % length_b],
                    vertex_view_y_b[(i1 + 1) % length_b], vertex_view_x_b[i1],
                    vertex_view_y_b[i1], vertex_view_y_b[j1])

                let l16 = vertex_view_x_b[j1]

                if (m307(l2, k7, i12, l16, flag)) {
                    return true
                }

                j1 = (j1 + 1) % length_b

                if (i1 == j1) {
                    byte0 = 2
                }
            }
        } else if (vertex_view_y_a[l] < vertex_view_y_b[i1]) {
            if (vertex_view_y_a[l] < vertex_view_y_b[j1]) {
                let i3 = m306(vertex_view_x_a[(k + 1) % length_a],
                                         vertex_view_y_a[(k + 1) % length_a],
                                         vertex_view_x_a[k], vertex_view_y_a[k],
                                         vertex_view_y_a[l])

                let l7 = vertex_view_x_a[l]

                let j12 = m306(
                    vertex_view_x_b[(i1 + 1) % length_b],
                    vertex_view_y_b[(i1 + 1) % length_b], vertex_view_x_b[i1],
                    vertex_view_y_b[i1], vertex_view_y_a[l])

                let i17 = m306(
                    vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_x_b[j1], vertex_view_y_b[j1],
                    vertex_view_y_a[l])

                if (m307(i3, l7, j12, i17, flag)) {
                    return true
                }

                l = (l + 1) % length_a

                if (k == l) {
                    byte0 = 1
                }
            } else {
                let j3 = m306(vertex_view_x_a[(k + 1) % length_a],
                                         vertex_view_y_a[(k + 1) % length_a],
                                         vertex_view_x_a[k], vertex_view_y_a[k],
                                         vertex_view_y_b[j1])

                let i8 = m306(
                    vertex_view_x_a[(l - 1 + length_a) % length_a],
                    vertex_view_y_a[(l - 1 + length_a) % length_a],
                    vertex_view_x_a[l], vertex_view_y_a[l],
                    vertex_view_y_b[j1])

                let k12 = m306(
                    vertex_view_x_b[(i1 + 1) % length_b],
                    vertex_view_y_b[(i1 + 1) % length_b], vertex_view_x_b[i1],
                    vertex_view_y_b[i1], vertex_view_y_b[j1])

                let j17 = vertex_view_x_b[j1]

                if (m307(j3, i8, k12, j17, flag)) {
                    return true
                }

                j1 = (j1 + 1) % length_b

                if (i1 == j1) {
                    byte0 = 2
                }
            }
        } else if (vertex_view_y_b[i1] < vertex_view_y_b[j1]) {
            let k3 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_b[i1])

            let j8 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_b[i1])

            let l12 = vertex_view_x_b[i1]

            let k17 = m306(
                vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_b[i1])

            if (m307(k3, j8, l12, k17, flag)) {
                return true
            }

            i1 = (i1 - 1 + length_b) % length_b

            if (i1 == j1) {
                byte0 = 2
            }
        } else {
            let l3 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_b[j1])

            let k8 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_b[j1])

            let i13 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_b[j1])

            let l17 = vertex_view_x_b[j1]

            if (m307(l3, k8, i13, l17, flag)) {
                return true
            }

            j1 = (j1 + 1) % length_b

            if (i1 == j1) {
                byte0 = 2
            }
        }
    }

    while (byte0 == 1) {
        if (vertex_view_y_a[k] < vertex_view_y_b[i1]) {
            if (vertex_view_y_a[k] < vertex_view_y_b[j1]) {
                let i4 = vertex_view_x_a[k]

                let j13 = m306(
                    vertex_view_x_b[(i1 + 1) % length_b],
                    vertex_view_y_b[(i1 + 1) % length_b], vertex_view_x_b[i1],
                    vertex_view_y_b[i1], vertex_view_y_a[k])

                let i18 = m306(
                    vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                    vertex_view_x_b[j1], vertex_view_y_b[j1],
                    vertex_view_y_a[k])

                return m308(j13, i18, i4, !flag)
            }

            let j4 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_b[j1])

            let l8 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_b[j1])

            let k13 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_b[j1])

            let j18 = vertex_view_x_b[j1]

            if (m307(j4, l8, k13, j18, flag)) {
                return true
            }

            j1 = (j1 + 1) % length_b

            if (i1 == j1) {
                byte0 = 0
            }
        } else if (vertex_view_y_b[i1] < vertex_view_y_b[j1]) {
            let k4 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_b[i1])

            let i9 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_b[i1])

            let l13 = vertex_view_x_b[i1]

            let k18 = m306(
                vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_b[i1])

            if (m307(k4, i9, l13, k18, flag)) {
                return true
            }

            i1 = (i1 - 1 + length_b) % length_b

            if (i1 == j1) {
                byte0 = 0
            }
        } else {
            let l4 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_b[j1])

            let j9 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_b[j1])

            let i14 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_b[j1])

            let l18 = vertex_view_x_b[j1]

            if (m307(l4, j9, i14, l18, flag)) {
                return true
            }

            j1 = (j1 + 1) % length_b

            if (i1 == j1) {
                byte0 = 0
            }
        }
    }

    while (byte0 == 2) {
        if (vertex_view_y_b[i1] < vertex_view_y_a[k]) {
            if (vertex_view_y_b[i1] < vertex_view_y_a[l]) {
                let i5 = m306(vertex_view_x_a[(k + 1) % length_a],
                                         vertex_view_y_a[(k + 1) % length_a],
                                         vertex_view_x_a[k], vertex_view_y_a[k],
                                         vertex_view_y_b[i1])

                let k9 = m306(
                    vertex_view_x_a[(l - 1 + length_a) % length_a],
                    vertex_view_y_a[(l - 1 + length_a) % length_a],
                    vertex_view_x_a[l], vertex_view_y_a[l],
                    vertex_view_y_b[i1])

                let j14 = vertex_view_x_b[i1]

                return m308(i5, k9, j14, flag)
            }

            let j5 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_a[l])

            let l9 = vertex_view_x_a[l]

            let k14 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_a[l])

            let i19 = m306(
                vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_a[l])

            if (m307(j5, l9, k14, i19, flag)) {
                return true
            }

            l = (l + 1) % length_a

            if (k == l) {
                byte0 = 0
            }
        } else if (vertex_view_y_a[k] < vertex_view_y_a[l]) {
            let k5 = vertex_view_x_a[k]

            let i10 = m306(
                vertex_view_x_a[(l - 1 + length_a) % length_a],
                vertex_view_y_a[(l - 1 + length_a) % length_a],
                vertex_view_x_a[l], vertex_view_y_a[l], vertex_view_y_a[k])

            let l14 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_a[k])

            let j19 = m306(
                vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_a[k])

            if (m307(k5, i10, l14, j19, flag)) {
                return true
            }

            k = (k - 1 + length_a) % length_a

            if (k == l) {
                byte0 = 0
            }
        } else {
            let l5 = m306(vertex_view_x_a[(k + 1) % length_a],
                                     vertex_view_y_a[(k + 1) % length_a],
                                     vertex_view_x_a[k], vertex_view_y_a[k],
                                     vertex_view_y_a[l])

            let j10 = vertex_view_x_a[l]

            let i15 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                      vertex_view_y_b[(i1 + 1) % length_b],
                                      vertex_view_x_b[i1], vertex_view_y_b[i1],
                                      vertex_view_y_a[l])

            let k19 = m306(
                vertex_view_x_b[(j1 - 1 + length_b) % length_b],
                vertex_view_y_b[(j1 - 1 + length_b) % length_b],
                vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_a[l])

            if (m307(l5, j10, i15, k19, flag)) {
                return true
            }

            l = (l + 1) % length_a

            if (k == l) {
                byte0 = 0
            }
        }
    }

    if (vertex_view_y_a[k] < vertex_view_y_b[i1]) {
        let i6 = vertex_view_x_a[k]

        let j15 = m306(vertex_view_x_b[(i1 + 1) % length_b],
                                  vertex_view_y_b[(i1 + 1) % length_b],
                                  vertex_view_x_b[i1], vertex_view_y_b[i1],
                                  vertex_view_y_a[k])

        let l19 = m306(
            vertex_view_x_b[(j1 - 1 + length_b) % length_b],
            vertex_view_y_b[(j1 - 1 + length_b) % length_b],
            vertex_view_x_b[j1], vertex_view_y_b[j1], vertex_view_y_a[k])

        return m308(j15, l19, i6, !flag)
    }

    let j6 =
        m306(vertex_view_x_a[(k + 1) % length_a],
                        vertex_view_y_a[(k + 1) % length_a], vertex_view_x_a[k],
                        vertex_view_y_a[k], vertex_view_y_b[i1])

    let k10 = m306(vertex_view_x_a[(l - 1 + length_a) % length_a],
                              vertex_view_y_a[(l - 1 + length_a) % length_a],
                              vertex_view_x_a[l], vertex_view_y_a[l],
                              vertex_view_y_b[i1])

    let k15 = vertex_view_x_b[i1]

    return m308(j6, k10, k15, flag)
    }
}
