


def makeDurationList(renderList, patternLength):
    # renderList is [time, setOfHits] but want to make it [time, hitStr] because we know there's only 1 hit per set
    # for this use case
    rl = [[e[0], list(e[1])[0]] for e in renderList] 

    newHits = [h for h in range(len(rl)) if rl[h][0] != '=' or rl[h][0] != '~']

    def getDur(hitInd):
        i = 1
        while hitInd+i < len(rl) and rl[hitInd+i] == '=':
            i += 1
        endTime = patternLength if hitInd+i == len(rl) else rl[hitInd+i][0]
        return endTime - rl[hitInd][0]

    getDurSymbol = lambda h: set([str(rl[h][1])+'/'+str(getDur(h))]) #symbol is now 'hitStr/dur'

    newList = [[rl[h][0], getDurSymbol(h)] for h in newHits]
    return newList


class DurationPostProcessor:

    def process(self, renderList, patternLength):
        return makeDurationList(renderList, patternLength)
        


class RampPostProcessor:

    def __init__(self, startVal):
        self.startVal = startVal

    def process(self, renderList, patternLength):
        renderList[0] = [0.01, renderList[1]]
        renderList.insert(0, (0, set([self.startVal])))
        return makeDurationList(renderList, patternLength)
