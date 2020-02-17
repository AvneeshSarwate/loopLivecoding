


def makeDurationList(renderList):
    # renderList is [time, setOfHits] but want to make it [time, hitStr] because we know there's only 1 hit per set
    # for this use case
    rl = [[e[0], list(e[1])[0]] for e in renderList] 

    newHits = [h for h in range(len(rl)) if rl[h][0] != '=' or rl[h][0] != '~']

    def getDur(hitInd):
        i = 0
        while rl[hitInd+i] == '=':
            i++
        return rl[hitInd+i][0] - rl[hitInd][0]

    getDurSymbol = lambda h: set([rl[h][1]+'/'+str(getDur(h))]) #symbol is now 'hitStr/dur'

    newList = [[rl[h][0], getDurSymbol(h)] for h in newHits]


class DurationPostProcessor:

    def process(self, renderList):
        return makeDurationList(renderList)
        


class RampPostProcessor:

    def process(self, renderList):
        # renderList is [time, setOfHits] but want to make it [time, hitStr] because we know there's only 1 hit per set
        # for this use case
        rl = [[e[0], list(e[1])[0]] for e in renderList] 

        newHits = [h for h in range(len(rl)) if rl[h][0] != '=' or rl[h][0] != '~']

        def getDur(hitInd):
            i = 0
            while rl[hitInd+i] == '=':
                i++
            return rl[hitInd+i][0] - rl[hitInd][0]

        getDurSymbol = lambda h: set([rl[h][1]+'/'+str(getDur(h))]) #symbol is now 'hitStr/dur'

        newList = [[rl[h][0], getDurSymbol(h)] for h in newHits]