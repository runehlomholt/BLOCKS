from sqlalchemy import func

from .. import models


def completed_orders(db, respondent_id):
    return {
        row[0]
        for row in db.query(models.VignetteResponse.vignette_order)
        .filter(models.VignetteResponse.respondent_id == respondent_id)
        .distinct()
        .all()
    }


def next_order(db, respondent):
    total = db.query(func.count(models.AssignedVignette.id)).filter(
        models.AssignedVignette.respondent_id == respondent.id
    ).scalar() or 0
    done = completed_orders(db, respondent.id)
    for order in range(1, total + 1):
        if order not in done:
            return order
    return total + 1
